# tests/fixtures/ci/rt22-violation.Dockerfile
#
# DELIBERATELY VIOLATION-SHAPED — RT-22 golden-test fixture per ARCH §6 Phase 5
# detail item (e). Violates BOTH catch criteria (i) and (ii) of the RT-22 fence.
#
# CI inversion check (per Sec rubric (b)2 + ARCH §6.1 RT-22 row):
#   The RT-22 fence script MUST report violation against this fixture. If the
#   fence script reports clean, CI fails closed — the fence is broken.
#
# Fixture path discipline (per Sec rubric (b)3 + agent-def):
#   This file lives at tests/fixtures/ci/ and is excluded from production build
#   contexts via .dockerignore at repo root. It is NEVER built as a real container;
#   it exists solely for the RT-22 fence script to scan.
#
# DO NOT use this Dockerfile as a template for any production work.

FROM node:20-bookworm-slim

# Violates criterion (i) — SUPABASE_* env vars.
ENV SUPABASE_URL=https://example.supabase.co
ENV SUPABASE_SERVICE_ROLE_KEY=fake-key-for-fixture
ARG SUPABASE_ANON_KEY=fake-anon-key-for-fixture

# Violates criterion (ii)(a) — apt install postgresql-client.
RUN apt-get update && apt-get install -y postgresql-client

# Violates criterion (ii)(c) — pip install psycopg2-binary + asyncpg.
RUN pip install psycopg2-binary asyncpg

# Violates criterion (ii)(b) — npm install pg + node-postgres.
RUN npm install pg node-postgres

CMD ["node", "fixture.js"]
