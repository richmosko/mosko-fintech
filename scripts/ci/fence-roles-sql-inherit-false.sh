#!/usr/bin/env bash
#
# fence-roles-sql-inherit-false — Sec H2 ruling condition C-a: asserts the
# COMMITTED BLOB of supabase/roles.sql carries `grant pfin_owner to migrator
# with inherit false` AND `grant pfin_owner to postgres with inherit false`.
#
# WHY THIS MUST READ THE COMMITTED BLOB, NOT LIVE CI STATE. CI's own
# start-local-stack composite action and scripts/db-template-build.sh both
# re-grant `pfin_owner to postgres WITH INHERIT TRUE` as a NAMED, CI-only
# step (Sec H2, condition C-b) — harness-only owner-implicit reach, never
# meant to touch the committed file. A leg that queried the running CI
# database's own pg_auth_members would see INHERIT TRUE and could not tell
# a correct commit from a broken one: the claim this fence proves is about
# what PRODUCTION applies (the artefact — supabase/roles.sql as committed to
# `main`), not about what this ephemeral CI container currently holds. Sec's
# exact condition: "the leg must assert the COMMITTED BLOB of roles.sql, not
# the worktree file, and it must run in CI." A worktree read asserts what
# the checkout happens to contain, which can be dirty or mid-edit; the claim
# is about the tree at a specific ref.
#
# WHY A CI FENCE, NOT A pgTAP BATTERY LEG. pgTAP tests assert live database
# state (pg_catalog, pg_auth_members) — exactly the thing this fence must
# NOT read, per the reasoning above. There is no SQL-visible representation
# of "what the git blob at this ref contains," so this check runs outside
# the database, over `git show <ref>:supabase/roles.sql`.
#
# CATCH CRITERION: the committed blob at REF (default HEAD) must contain,
# verbatim modulo whitespace, both:
#   grant pfin_owner to migrator with inherit false
#   grant pfin_owner to postgres with inherit false
# (the trailing `, set true` and statement terminator are not asserted —
# only the INHERIT FALSE posture, which is the property Sec's condition is
# about; a future change to the SET clause alone should not trip this fence).
#
# Usage: fence-roles-sql-inherit-false.sh [ref] [path-to-roles.sql-in-repo]
# Exit 0: both grants present with inherit false.
# Exit 1: one or both grants are missing or carry inherit true -- VIOLATION.
# Exit 2: the ref/path could not be read -- environment problem, distinct
#         from a caught violation.
set -euo pipefail

REF="${1:-HEAD}"
RELPATH="${2:-supabase/roles.sql}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

BLOB="$(git show "${REF}:${RELPATH}" 2>&1)" || {
  echo "FATAL: could not read the committed blob at ${REF}:${RELPATH} -- ref or path wrong?" >&2
  echo "$BLOB" >&2
  exit 2
}

FAIL=0

if ! printf '%s\n' "$BLOB" | grep -qiE 'grant[[:space:]]+pfin_owner[[:space:]]+to[[:space:]]+migrator[[:space:]]+with[[:space:]]+inherit[[:space:]]+false'; then
  echo "VIOLATION: ${REF}:${RELPATH} does not carry 'grant pfin_owner to migrator with inherit false'." >&2
  FAIL=1
fi

if ! printf '%s\n' "$BLOB" | grep -qiE 'grant[[:space:]]+pfin_owner[[:space:]]+to[[:space:]]+postgres[[:space:]]+with[[:space:]]+inherit[[:space:]]+false'; then
  echo "VIOLATION: ${REF}:${RELPATH} does not carry 'grant pfin_owner to postgres with inherit false'." >&2
  FAIL=1
fi

if [ "$FAIL" -eq 1 ]; then
  echo "" >&2
  echo "fence-roles-sql-inherit-false: ${REF}:${RELPATH} FAILED (Sec H2 condition C-a)." >&2
  echo "The CI-only harness re-grant (pfin_owner to postgres WITH INHERIT TRUE, a NAMED" >&2
  echo "step in .github/actions/start-local-stack and scripts/db-template-build.sh) must" >&2
  echo "NEVER be mirrored into the committed supabase/roles.sql -- production's posture" >&2
  echo "stays non-ambient (INHERIT FALSE, SET TRUE), always requiring an explicit SET" >&2
  echo "ROLE. If this fired on a real change to roles.sql, that change widened" >&2
  echo "production's own membership grant and needs Sec joint-review, not a fence fix." >&2
  exit 1
fi

echo "fence-roles-sql-inherit-false: ${REF}:${RELPATH} clean -- both pfin_owner memberships (migrator, postgres) committed with INHERIT FALSE."
exit 0
