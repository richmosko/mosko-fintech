#!/usr/bin/env bash
#
# fake-step.sh -- generic stand-in for every script scripts/provision.sh
# shells out to, used by scripts/ci/fence-provision-strikes.sh. Symlinked
# under each real script's name inside a fixture scripts/ dir that
# provision.sh's SCRIPTS override points at.
#
# Per-name behavior is controlled by two env vars, NAME uppercased with
# `-` -> `_`:
#   FAKE_RC_<NAME>            comma-separated exit codes, one per call to
#                             this name (cycles/holds on the last entry
#                             once exhausted) -- lets a compound step's
#                             Nth sub-call fail on purpose. Default "0".
#   FAKE_CALL_LOG             if set, every invocation appends
#                             "<name> <args...>" to this file -- lets the
#                             fence assert which steps' --apply actually
#                             ran (e.g. proving --dry-run never fires one).

set -euo pipefail

NAME="$(basename "$0" .sh)"
VARNAME="FAKE_RC_${NAME//-/_}"
RC_LIST="${!VARNAME:-0}"

COUNTER_FILE="${FAKE_COUNTER_DIR:-/tmp}/.fake-step-counter.$NAME"
CALL_N=1
if [[ -f "$COUNTER_FILE" ]]; then
  CALL_N=$(($(cat "$COUNTER_FILE") + 1))
fi
echo "$CALL_N" > "$COUNTER_FILE"

IFS=',' read -r -a RC_ARR <<< "$RC_LIST"
IDX=$((CALL_N - 1))
if [[ $IDX -ge ${#RC_ARR[@]} ]]; then
  IDX=$((${#RC_ARR[@]} - 1))
fi
RC="${RC_ARR[$IDX]}"

if [[ -n "${FAKE_CALL_LOG:-}" ]]; then
  printf '%s %s\n' "$NAME" "$*" >> "$FAKE_CALL_LOG"
fi

echo "FAKE $NAME call #$CALL_N -> exit $RC (args: $*)"
exit "$RC"
