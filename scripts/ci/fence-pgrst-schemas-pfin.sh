#!/usr/bin/env bash
#
# fence-pgrst-schemas-pfin.sh — CI-lane (repo) half of BACKLOG.md §7.36
# item 22's fence (Sec joint-review, F/CTO-ruled 2026-09-19; ADR-023's
# ratified Data-API exposure posture for `pfin`).
#
# WHY THIS IS ITS OWN SENTINEL, NOT A REUSE OF ANY OTHER FENCE'S. Per
# Sec's review: fence-datastore-private-bind.sh and fence-admission-
# private-bind.sh each assert a NETWORK-exposure property (what's bound
# to what interface); this fence asserts a DATA-API SCHEMA-exposure
# property (what PostgREST is told to serve). Reusing another fence's
# sentinel for a structurally different property is exactly the
# layer-attribution drift ADR-011 Decision 4 catalogues. This fence ships
# UNLABELED pending an F/CTO Decision-4 RT ratify (Sec/DevOps do not mint
# RT-NN numbers themselves).
#
# WHAT THIS FENCE CANNOT SEE, STATED SO IT IS NOT OVERSOLD: the box's
# ACTUAL running value in the Coolify env store. NONSECRET_DEFAULTS
# (subject 1 below) is check-if-absent, so correcting the committed
# default here does not correct an already-set live value -- see the
# SEPARATE production-observable half, scripts/ci/fence-pgrst-schemas-
# live.sh, wired into scripts/provision-supabase-stack.sh's own
# Verification battery, which is the only leg that observes the box.
#
# CATCH CRITERION: every subject below must express PGRST_DB_SCHEMAS as
# the EXACT ruled literal, in the EXACT ruled order --
# "public,graphql_public,pfin" -- never a set-membership match. PostgREST
# treats its FIRST listed schema as the default Accept-Profile, so
# "pfin,public,graphql_public" contains the right three names in the
# wrong order and would silently make `pfin` the default profile while
# un-exposing the other two -- a set-equality check would pass that
# fixture and miss the defect. This is why the golden fixtures below
# include an order-reversed case as the load-bearing negative, not merely
# a wrong-value case.
#
# Subjects (all three required; each parsed to ITS OWN committed shape,
# never a bare-string grep across the whole file):
#   1. scripts/provision-supabase-stack.sh -- the NONSECRET_DEFAULTS
#      Python dict literal's "PGRST_DB_SCHEMAS": "..." entry (check-if-
#      absent; this is what a fresh, never-touched Coolify resource gets).
#   2. infra/supabase/docker-compose.yml -- both PGRST_DB_SCHEMAS:
#      env-var sites on the `rest` and `meta` services must remain PURE
#      ${PGRST_DB_SCHEMAS} interpolation with no hardcoded literal and no
#      `:-fallback` default -- a hardcoded value here would silently
#      override whatever the env store says, which is the exact silent-
#      divergence class this whole item exists to close.
#   3. docs/deployment-runbook.md -- every `PGRST_DB_SCHEMAS=<value>`
#      example string in the prose must equal the ruled literal.
#
# Usage:
#   fence-pgrst-schemas-pfin.sh <provision-script> <compose-file> <runbook-file>
#
# Exit codes:
#   0 -- all three subjects clean.
#   1 -- one or more subjects VIOLATE (each named on stderr).
#   2 -- a file is missing, or a subject's expected shape was not found at
#        all (the file's own structure changed -- update this fence's
#        parser to match, do not treat "found zero" as "clean").

set -euo pipefail

RULED_LITERAL="public,graphql_public,pfin"

PROVISION_SCRIPT="${1:?Usage: fence-pgrst-schemas-pfin.sh <provision-script> <compose-file> <runbook-file>}"
COMPOSE_FILE="${2:?Usage: fence-pgrst-schemas-pfin.sh <provision-script> <compose-file> <runbook-file>}"
RUNBOOK_FILE="${3:?Usage: fence-pgrst-schemas-pfin.sh <provision-script> <compose-file> <runbook-file>}"

for f in "$PROVISION_SCRIPT" "$COMPOSE_FILE" "$RUNBOOK_FILE"; do
  [[ -f "$f" ]] || { echo "FATAL: file not found: $f" >&2; exit 2; }
done

VIOLATIONS=0

# ── Subject 1: provision-supabase-stack.sh NONSECRET_DEFAULTS ──────────────
# Parsed with plain parameter expansion (portable across BSD/GNU sed's
# differing \s support) rather than a regex capture group.
DEFAULT_LINE="$(grep -E '"PGRST_DB_SCHEMAS"[[:space:]]*:[[:space:]]*"' "$PROVISION_SCRIPT" | tail -1 || true)"
if [[ -z "$DEFAULT_LINE" ]]; then
  echo "FATAL: no \"PGRST_DB_SCHEMAS\": \"...\" entry found in $PROVISION_SCRIPT's NONSECRET_DEFAULTS -- did the dict key get renamed or removed? Update this fence's parser to match." >&2
  exit 2
fi
_tmp="${DEFAULT_LINE#*\"PGRST_DB_SCHEMAS\"}"   # -> : "value",
_tmp="${_tmp#*\"}"                              # -> value",
DEFAULT_VALUE="${_tmp%%\"*}"                    # -> value
if [[ "$DEFAULT_VALUE" != "$RULED_LITERAL" ]]; then
  echo "VIOLATION ($PROVISION_SCRIPT): NONSECRET_DEFAULTS[\"PGRST_DB_SCHEMAS\"] = \"$DEFAULT_VALUE\", expected the exact ruled literal \"$RULED_LITERAL\" (public FIRST; BACKLOG.md §7.36 item 22)." >&2
  VIOLATIONS=1
fi

# ── Subject 2: docker-compose.yml — pure interpolation, both sites ─────────
# Plain grep (no line numbers -- a line-number prefix would itself contain
# a colon and break the parameter-expansion split below).
COMPOSE_LINES="$(grep -E '^[[:space:]]*PGRST_DB_SCHEMAS:' "$COMPOSE_FILE" || true)"
COMPOSE_COUNT=0
[[ -n "$COMPOSE_LINES" ]] && COMPOSE_COUNT="$(printf '%s\n' "$COMPOSE_LINES" | grep -c .)"
if [[ "$COMPOSE_COUNT" -eq 0 ]]; then
  echo "FATAL: no PGRST_DB_SCHEMAS: env key found in $COMPOSE_FILE -- did the rest/meta service blocks change shape? Update this fence's parser to match." >&2
  exit 2
fi
if [[ "$COMPOSE_COUNT" -ne 2 ]]; then
  echo "FATAL: expected exactly 2 PGRST_DB_SCHEMAS: sites in $COMPOSE_FILE (rest + meta services), found $COMPOSE_COUNT -- a service was added/removed, or this fence's coverage assumption is stale. Update the parser, do not silently pass a changed count." >&2
  exit 2
fi
while IFS= read -r line; do
  content="${line#*PGRST_DB_SCHEMAS:}"
  # trim leading/trailing whitespace via word-splitting (no sed \s needed)
  content="$(echo $content)"
  if [[ "$content" != '${PGRST_DB_SCHEMAS}' ]]; then
    echo "VIOLATION ($COMPOSE_FILE): PGRST_DB_SCHEMAS: is not pure \${PGRST_DB_SCHEMAS} interpolation -- found \"$content\". A hardcoded literal or a :-fallback here silently overrides whatever the env store says, defeating the whole reconciliation." >&2
    VIOLATIONS=1
  fi
done <<< "$COMPOSE_LINES"

# ── Subject 3: deployment-runbook.md — every example string ────────────────
RUNBOOK_MATCHES="$(grep -oE "PGRST_DB_SCHEMAS=[\"'\`]?[A-Za-z0-9_,]+" "$RUNBOOK_FILE" || true)"
if [[ -z "$RUNBOOK_MATCHES" ]]; then
  echo "FATAL: no PGRST_DB_SCHEMAS=<value> example found in $RUNBOOK_FILE -- the prose that this fence exists to pin is gone. Update this fence's parser (or restore the example); 'found zero' is not 'clean'." >&2
  exit 2
fi
while IFS= read -r match; do
  value="${match#PGRST_DB_SCHEMAS=}"
  value="${value#[\"\'\`]}"
  if [[ "$value" != "$RULED_LITERAL" ]]; then
    echo "VIOLATION ($RUNBOOK_FILE): example \"$match\" does not match the exact ruled literal \"PGRST_DB_SCHEMAS=$RULED_LITERAL\"." >&2
    VIOLATIONS=1
  fi
done <<< "$RUNBOOK_MATCHES"

if [[ "$VIOLATIONS" -ne 0 ]]; then
  echo "" >&2
  echo "fence-pgrst-schemas-pfin FAILED -- see VIOLATION lines above. This fence checks the COMMITTED repo default and prose only; it cannot see the live Coolify store (see fence-pgrst-schemas-live.sh for that half)." >&2
  exit 1
fi

echo "fence-pgrst-schemas-pfin: all three subjects clean (ruled literal: $RULED_LITERAL)."
exit 0
