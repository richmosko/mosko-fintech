#!/usr/bin/env bash
#
# fake-step.sh -- generic stand-in for every script scripts/provision.sh
# shells out to, used by scripts/ci/fence-provision-strikes.sh. Symlinked
# under each real script's name inside a fixture scripts/ dir that
# provision.sh's SCRIPTS override points at.
#
# Per-name behavior is controlled by two env vars, NAME LOWERCASE with
# `-` -> `_` (verbatim from `basename "$0" .sh`, NEVER uppercased --
# corrected 2026-09-21, team-lead's run-6 stop item 10, after this
# comment's own claim caused a real defect: a new caller assumed
# uppercase and its default silently never took effect):
#   FAKE_RC_<NAME>            comma-separated exit codes, one per call to
#                             this name (cycles/holds on the last entry
#                             once exhausted) -- lets a compound step's
#                             Nth sub-call fail on purpose. Default "0".
#   FAKE_CALL_LOG             if set, every invocation appends
#                             "<name> BOX_IP=<value-or-ABSENT> <args...>"
#                             to this file -- lets the fence assert which
#                             steps' --apply actually ran (e.g. proving
#                             --dry-run never fires one) AND, per-name,
#                             whether provision.sh's own require_box_ip
#                             mechanism (D-1, live --dry-run, 2026-09-20)
#                             actually reached this call's environment --
#                             the BOX_IP=<value> field is what that
#                             scenario greps for, never presence/absence
#                             of an argv token (this repo's own scripts
#                             take BOX_IP via environment, never argv).
#   FAKE_STDOUT_<NAME>        if set, printed verbatim (its own line)
#                             BEFORE the "FAKE ..." line, on every call to
#                             this name -- lets a scenario simulate a real
#                             script's own lenient/informational stdout
#                             text (e.g. record-coolify-uuids.sh's own
#                             "no application named 'X' found yet" line,
#                             printed even though ITS OWN exit code is 0)
#                             for provision.sh's live_done_provision_
#                             resources() to grep (live --dry-run
#                             BLOCKED-BY classifier follow-up,
#                             2026-09-20). Never affects FAKE_RC_<NAME>.
#   FAKE_STDOUT_LIST_<NAME>   PIPE-delimited (never comma -- a real
#                             "current state: fqdn=SET (...), ports_
#                             exposes=ABSENT" line contains commas), ONE
#                             ENTRY PER CALL to this name, same cycle/
#                             hold-on-last-entry semantics as FAKE_RC_
#                             <NAME> above. Added 2026-09-21 (deploy-
#                             workers resume-path re-read fix): the
#                             single-value FAKE_STDOUT_<NAME> cannot
#                             express "this name's Nth call reports a
#                             DIFFERENT state than its (N-1)th" (e.g.
#                             SET before a clear, ABSENT/EMPTY on the
#                             POST-clear re-read) -- a fixture "restating
#                             the lie" on every call is exactly the shape
#                             that let a real fail-open regression here
#                             go undetected. Takes precedence over
#                             FAKE_STDOUT_<NAME> when set; falls back to
#                             it (unchanged, every existing scenario byte-
#                             identical) when unset.

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

STDOUT_LIST_VARNAME="FAKE_STDOUT_LIST_${NAME//-/_}"
STDOUT_VARNAME="FAKE_STDOUT_${NAME//-/_}"
if [[ -n "${!STDOUT_LIST_VARNAME:-}" ]]; then
  IFS='|' read -r -a STDOUT_ARR <<< "${!STDOUT_LIST_VARNAME}"
  SIDX=$((CALL_N - 1))
  if [[ $SIDX -ge ${#STDOUT_ARR[@]} ]]; then
    SIDX=$((${#STDOUT_ARR[@]} - 1))
  fi
  if [[ -n "${STDOUT_ARR[$SIDX]:-}" ]]; then
    printf '%s\n' "${STDOUT_ARR[$SIDX]}"
  fi
elif [[ -n "${!STDOUT_VARNAME:-}" ]]; then
  printf '%s\n' "${!STDOUT_VARNAME}"
fi

if [[ -n "${FAKE_CALL_LOG:-}" ]]; then
  printf '%s BOX_IP=%s %s\n' "$NAME" "${BOX_IP:-<ABSENT>}" "$*" >> "$FAKE_CALL_LOG"
fi

echo "FAKE $NAME call #$CALL_N -> exit $RC (args: $*)"
exit "$RC"
