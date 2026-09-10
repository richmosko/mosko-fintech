#!/usr/bin/env bash
#
# fence-tinker-no-echo — interactive-tinker CI fence (Sec spec, 2026-09-11).
#
# ⚠ NOT YET A CATALOGUED §10 INSTANCE / CI-FENCED-SET MEMBER BY NAME.
# Assigning this fence an RT-NN id is an F/CTO Decision-4 ratify act, not
# DevOps's or Sec's to mint by shipping a label — same precedent as
# fence-datastore-private-bind.sh, which ships unlabeled for the identical
# reason. Do not add an RT-NN string anywhere in this file, its CI job, or
# its fixtures until F/CTO ratifies one; the fence protects the tree
# regardless of whether it carries a catalog id yet.
#
# WHY THIS EXISTS. Security incident, 2026-09-11: `provision-vps.sh` piped a
# script into interactive tinker (no --execute) over `docker exec -i` to
# mint a Coolify automation token. Measured on the real --apply
# run: interactive/piped tinker echoes each input line back (`> ...`) AND
# the return value of evaluated expressions (`= ...`) to its own stdout — a
# REPL transcript, not a clean script run. The token's plaintext reached the
# operator's terminal and the run log BEFORE the script's own leak-check
# (which watched a different stream) ever ran. Fixed at the mechanism in
# provision-vps.sh: `tinker --execute=<code>` (Laravel's documented
# non-interactive mode; no REPL echo of input or return values). This fence
# is the mechanical guarantee that the fix doesn't rot and that the same
# defect class doesn't reappear anywhere else under scripts/ — it would have
# caught the incident, and it caught a second (non-leaking, but same-class)
# instance in scripts/coolify-materialize-supabase-mounts.sh during triage.
#
# CATCH CRITERION (Sec's exact spec — do not soften):
#   grep -rnE 'artisan tinker' scripts/ --include='*.sh' | grep -v -- '--execute'
#   must be EMPTY: a line naming tinker with no --execute on that same line
#   is a violation.
#
# ⚠ THIS IS A BLUNT, LINE-LEVEL, GREP-BASED CHECK — DELIBERATELY, matching
# this repo's existing fence convention (see fence-rt26-service-role-
# allowlist.sh's own header: "the AUDIT side is grep-based too... behaviour
# is at least SYMMETRIC"). It cannot distinguish a live interactive
# invocation from a comment or an echoed status string that happens to say
# "artisan tinker" without "--execute" on the same line — and it does not
# try to. A comment describing the OLD broken mechanism trips this exactly
# as code would; the fix in both is the same: make it true, don't special-
# case the fence. It also cannot catch a violation split across two lines
# (e.g. `--execute=\` continued on the next line) — a known, accepted gap,
# same shape as every other line-oriented fence in this repo.
#
# Usage:
#   bash fence-tinker-no-echo.sh <scope-dir>
#
#   <scope-dir>   Directory to scan (e.g. scripts/, or a golden-fixture dir
#                 for inversion-mode). Only *.sh files under it are scanned.
#
# Exit codes:
#   0   — scope clean (zero interactive-tinker lines).
#   1   — one or more violations found. A statement about the CODE.
#   2   — argument / environment error (bad scope path). The scan did not run.
#
set -euo pipefail

SCOPE="${1:-}"
if [ -z "$SCOPE" ]; then
  echo "FATAL: missing scope argument." >&2
  echo "Usage: bash $(basename "$0") <scope-dir>" >&2
  exit 2
fi
if [ ! -d "$SCOPE" ]; then
  echo "FATAL: scope is not a directory: $SCOPE" >&2
  exit 2
fi

# `|| true` so an empty grep result (the pass case) doesn't trip -e.
HITS=$(grep -rnE 'artisan tinker' "$SCOPE" --include='*.sh' 2>/dev/null | grep -v -- '--execute' || true)

if [ -n "$HITS" ]; then
  echo "VIOLATION: 'artisan tinker' invoked without --execute on the same line:" >&2
  echo "$HITS" | sed 's/^/  /' >&2
  echo "" >&2
  echo "interactive-tinker fence: scope $SCOPE failed. Failing closed." >&2
  echo "" >&2
  echo "Piped/interactive tinker echoes an input+return-value transcript to its" >&2
  echo "own stdout — this is how the 2026-09-11 token-leak incident happened." >&2
  echo "Fix: use 'php artisan tinker --execute=<code>' instead (Laravel's" >&2
  echo "documented non-interactive mode — no REPL echo). If the hit is a" >&2
  echo "comment or status string mentioning tinker in prose, not code, reword" >&2
  echo "it rather than exempting it — this fence does not special-case comments," >&2
  echo "matching every other grep-based fence in this repo." >&2
  exit 1
fi

echo "interactive-tinker fence: scope $SCOPE clean (every 'artisan tinker' invocation uses --execute)."
exit 0
