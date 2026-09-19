#!/usr/bin/env bash
#
# fence-pgrst-schemas-live.sh — production-observable half of BACKLOG.md
# §7.36 item 22's fence (Sec joint-review, F/CTO-ruled 2026-09-19; the
# ADR-023 exposure posture). This is NOT the CI-lane fence
# (fence-pgrst-schemas-pfin.sh checks the committed repo default) — the
# two are deliberately separate scripts because they check different
# things: the repo's DEFAULT vs. the box's ACTUAL running value.
#
# WHY THIS SCRIPT EXISTS, SEPARATE FROM THE CI FENCE. Per
# scripts/provision-supabase-stack.sh's own header on the sibling
# MIGRATOR_DB_* case: "MINT_SECRETS is mint-if-ABSENT, so simply removing
# them here would silently leave a PRE-EXISTING value in this resource's
# store untouched forever." The same is true of PGRST_DB_SCHEMAS's
# NONSECRET_DEFAULTS entry — it is check-if-absent, so correcting the
# repo's committed default does NOT correct an already-set Coolify env
# store value. A CI-green literal-match check over the repo alone would
# report success while the box still served the wrong (or previously-
# wrong) value — exactly the gap that let item 22 ship unnoticed in the
# first place (docs/records/v1final/standup-log.md §5f + its Departures
# row). This script is what observes the box, modeled on
# scripts/ci/check-migrator-names-absent.sh's own strike-proof shape
# (ADR-072 Amendment 4).
#
# Reads raw `env`-shaped output (`KEY=VALUE`, one per line — exactly what
# `docker compose ... exec -T rest env` prints) from a file argument or
# STDIN, and fails closed unless PGRST_DB_SCHEMAS's value is the EXACT
# ruled literal, in the EXACT ruled order: `public,graphql_public,pfin`.
#
# ⚠ ORDER MATTERS — THIS IS NOT A SET-MEMBERSHIP CHECK. PostgREST's first
# listed schema becomes its default `Accept-Profile` when a request sends
# none. `pfin,public,graphql_public` contains the right three names but
# would make `pfin` the default profile and is therefore WRONG — a
# set-equality check would pass it and miss the defect. This script does
# an exact string comparison for that reason, not a sorted/set comparison.
#
# Usage:
#   fence-pgrst-schemas-live.sh [<env-dump-file>]   # reads stdin if omitted
#
# Exit codes:
#   0 — PGRST_DB_SCHEMAS is present and equals exactly "public,graphql_public,pfin".
#   1 — PGRST_DB_SCHEMAS is present but its value differs (value named on
#       stderr — this is a non-secret, already-public Data-API exposure
#       setting, not a credential, so echoing it is safe).
#   2 — no input at all, or PGRST_DB_SCHEMAS absent as a name entirely —
#       cannot confirm the value over nothing to check; fail closed
#       rather than pass by default.

set -euo pipefail

RULED_LITERAL="public,graphql_public,pfin"

INPUT="${1:-/dev/stdin}"

RAW="$(cat "$INPUT" 2>/dev/null || true)"
if [[ -z "$RAW" ]]; then
  echo "FATAL: no input -- cannot confirm PGRST_DB_SCHEMAS over an empty env dump. Failing closed." >&2
  exit 2
fi

VALUE_LINE="$(printf '%s\n' "$RAW" | grep -E '^PGRST_DB_SCHEMAS=' | tail -1 || true)"

if [[ -z "$VALUE_LINE" ]]; then
  echo "FATAL: PGRST_DB_SCHEMAS not present as a name in this env dump -- cannot confirm its value over an absent name. Failing closed." >&2
  exit 2
fi

VALUE="${VALUE_LINE#PGRST_DB_SCHEMAS=}"

if [[ "$VALUE" != "$RULED_LITERAL" ]]; then
  echo "FAIL: PGRST_DB_SCHEMAS='$VALUE' -- expected the exact ruled literal '$RULED_LITERAL' (public FIRST; BACKLOG.md §7.36 item 22, F/CTO-ruled 2026-09-19)." >&2
  echo "This is an exact-string, order-sensitive check, not set membership -- 'pfin,public,graphql_public' has the right names in the wrong order and would make pfin the default Accept-Profile. Fix the live value, do not fix this check." >&2
  exit 1
fi

echo "OK: PGRST_DB_SCHEMAS is the exact ruled literal '$RULED_LITERAL'."
exit 0
