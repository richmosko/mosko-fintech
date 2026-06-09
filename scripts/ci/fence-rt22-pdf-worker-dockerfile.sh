#!/usr/bin/env bash
#
# RT-22 — PDF worker Dockerfile audit (zero-DB-isolation fence)
#
# Lock anchors:
#   - ADR-011 Decision 4 (first catalogued §10 instance; infrastructure-credential-presence layer)
#   - ADR-011 Decision 17 / Lock 13 mod #2
#   - SECURITY §4.5 RT-22 entry
#   - ARCH §6 Security scan stage (iii) + ARCH §6.1 RT-22 row
#   - ARCH §6 Phase 5 detail item (e)
#
# Catch criteria (BOTH enforced; Sec veto if either missing):
#   (i)  No SUPABASE_* env vars (ENV or ARG directives).
#         The single permitted env var per SD-20 is PDF_WORKER_SIGNING_KEY (not in
#         SUPABASE_* namespace; doesn't trip).
#   (ii) No Postgres client install (psycopg2 / psycopg2-binary / asyncpg / pg /
#        node-postgres / postgresql-client) via direct install verbs.
#
# Explicitly NOT catching at CI (covered by human PR-review per ARCH §6.1 RT-22 row):
#   - COPY of package.json / requirements.txt manifests (install intent revealed
#     at RUN time, not COPY time; manifest inspection is human-second-line).
#   - Transitive Postgres client via base image (not Dockerfile-grep-detectable).
#
# Usage:
#   bash fence-rt22-pdf-worker-dockerfile.sh <path-to-Dockerfile>
#
# Exit codes:
#   0   — Dockerfile clean (no violations).
#   1   — Dockerfile has one or more catch-criterion violations (fail-closed).
#   2   — Argument or environment error (target Dockerfile missing / unreadable).
#

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "FATAL: missing target Dockerfile arg." >&2
  echo "Usage: bash $(basename "$0") <path-to-Dockerfile>" >&2
  exit 2
fi
if [ ! -f "$TARGET" ]; then
  echo "FATAL: target Dockerfile not found at: $TARGET" >&2
  exit 2
fi

VIOLATIONS=0

# Criterion (i) — no SUPABASE_* env vars.
if grep -nE '^[[:space:]]*(ENV|ARG)[[:space:]]+SUPABASE_' "$TARGET"; then
  echo "VIOLATION (i): SUPABASE_* env var (ENV/ARG) found in $TARGET." >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

# Criterion (ii)(a) — apt/apk install of postgresql-client.
if grep -nE '^[[:space:]]*RUN[[:space:]].*(apt-get|apt)[[:space:]]+install.*postgresql-client' "$TARGET"; then
  echo "VIOLATION (ii)(a): apt install postgresql-client found in $TARGET." >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi
if grep -nE '^[[:space:]]*RUN[[:space:]].*apk[[:space:]]+add.*postgresql-client' "$TARGET"; then
  echo "VIOLATION (ii)(a): apk add postgresql-client found in $TARGET." >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

# Criterion (ii)(b) — npm/yarn/pnpm install of pg or node-postgres.
# Word-boundary match avoids false positives on substrings like "package", "image".
if grep -nE '^[[:space:]]*RUN[[:space:]].*(npm[[:space:]]+(install|i)|yarn[[:space:]]+add|pnpm[[:space:]]+add).*(\b|@)(pg|node-postgres)\b' "$TARGET"; then
  echo "VIOLATION (ii)(b): npm/yarn/pnpm install of pg or node-postgres found in $TARGET." >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

# Criterion (ii)(c) — pip install of psycopg2 / psycopg2-binary / asyncpg.
if grep -nE '^[[:space:]]*RUN[[:space:]].*pip[[:space:]]+install.*(psycopg2(-binary)?|asyncpg)' "$TARGET"; then
  echo "VIOLATION (ii)(c): pip install of psycopg2/psycopg2-binary/asyncpg found in $TARGET." >&2
  VIOLATIONS=$((VIOLATIONS+1))
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "RT-22 fence: $VIOLATIONS violation(s) in $TARGET. Failing closed." >&2
  echo "PDF worker Dockerfile must carry NO SUPABASE_* env vars and NO Postgres" >&2
  echo "client install per Lock 13 mod #2 (zero-DB-isolation). The single permitted" >&2
  echo "env var is PDF_WORKER_SIGNING_KEY per SD-20." >&2
  exit 1
fi

echo "RT-22 fence: $TARGET clean (no SUPABASE_* env vars; no Postgres client install)."
exit 0
