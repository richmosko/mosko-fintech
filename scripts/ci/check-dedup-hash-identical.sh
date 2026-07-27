#!/usr/bin/env bash
#
# dedup-hash-identical — SELF-204 / ADR-034 Decision 4 import_hash drift fence.
#
# Lock anchors:
#   - ADR-034 Decision 4 (F/CTO-ratified 2026-07-27): the canonical manual↔provider
#     import_hash is ONE shared source computed identically by both tiers; a divergent
#     canonicalization breaks dedup detection INVISIBLY. Location B (canonical source in
#     workers/provider-sync/, machine-generated banner-marked copy in api/).
#   - Sec ratify condition 2 (2026-07-27): the fence must be REGENERATE-and-assert-clean,
#     NOT a static two-file byte-compare. A static `cmp fileA fileB` passes if BOTH files
#     were hand-edited in lockstep and cannot distinguish a stale copy from a faithful one.
#     This fence instead runs the canonical generator FROM THE SOURCE and asserts the
#     committed copy IS byte-identical to that fresh generator output — red on ANY drift:
#       (a) source edited, copy not regenerated (stale copy),
#       (b) copy hand-edited away from generator output,
#       (c) copy deleted / absent (diff against a missing copy → drift, exit 1).
#
#   MECHANISM NOTE (flagged to Sec at build-time golden sign-off): Sec condition 2 named
#   `node <gen>` then `git diff --exit-code -- <copy>`. This script implements the SAME
#   regenerate-and-assert-clean PRINCIPLE but compares the generator's `--stdout` output
#   directly against the on-disk copy with `diff`, rather than regenerating in place +
#   `git diff`. Rationale: `git diff --exit-code` is git-index-state-sensitive — it
#   false-REDs when the copy is staged-but-uncommitted (a legitimate developer state
#   before the copy is committed) and is tracked-only, so it false-GREENs a deleted copy
#   unless hardened with `git add --intent-to-add` (which itself misbehaves on a
#   staged-new file). The `--stdout | diff` form is git-state-independent: identical in CI
#   and locally, and a missing copy fails closed naturally. Same catch set, no false red.
#
#   - Placement: security-scan.yml, RUN-ALWAYS (no `paths:` filter), fail-closed, and
#     registered as a REQUIRED status check on `main` (F/CTO branch-protection action,
#     post-first-report). A drift fence that isn't run-always is theater (the F-2 / RT-27
#     trigger-drift precedent: a path-filtered cross-tree fence green-by-absence when a PR
#     touches only one tree).
#
# Dual-mode via args (mirrors fence-rt22/rt26/tbc/secrets-nonoverlap):
#   PRODUCTION  — no args: real canonical source vs real committed copy → expect exit 0.
#   INVERSION   — golden fixtures (a source + a deliberately-diverged copy) → expect exit 1.
#     bash check-dedup-hash-identical.sh \
#       --source tests/fixtures/ci/dedup-hash-drift-source.ts \
#       --copy   tests/fixtures/ci/dedup-hash-drift-copy.ts
#
# Usage:
#   bash scripts/ci/check-dedup-hash-identical.sh
#     [--generator <path>]   (default: scripts/generate-import-hash-copy.mjs)
#     [--source <path>]      (default: workers/provider-sync/src/shared/importHash.ts)
#     [--copy <path>]        (default: api/src/lib/server/dedup/importHash.ts)
#
# Run from the repo root (matches the other security-scan.yml fences).
#
# Exit codes:
#   0 — copy IS current generator output (clean).
#   1 — drift: copy differs from generator output, or copy is missing (fail-closed).
#   2 — argument / environment error (generator or node missing).

set -euo pipefail

GENERATOR="scripts/generate-import-hash-copy.mjs"
SOURCE="workers/provider-sync/src/shared/importHash.ts"
COPY="api/src/lib/server/dedup/importHash.ts"

while [ $# -gt 0 ]; do
  case "$1" in
    --generator) GENERATOR="${2:-}"; shift 2 ;;
    --source)    SOURCE="${2:-}"; shift 2 ;;
    --copy)      COPY="${2:-}"; shift 2 ;;
    *) echo "FATAL: unknown argument: $1" >&2
       echo "Usage: bash $(basename "$0") [--generator <path>] [--source <path>] [--copy <path>]" >&2
       exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "FATAL: node not found on PATH (the generator is a Node .mjs script)." >&2
  exit 2
fi
if [ ! -f "$GENERATOR" ]; then
  echo "FATAL: generator not found at: $GENERATOR" >&2
  exit 2
fi
if [ ! -f "$SOURCE" ]; then
  echo "FATAL: canonical source not found at: $SOURCE" >&2
  exit 2
fi

# Fail-closed on a missing/deleted copy — a copy that was removed from the commit must be
# caught as drift, not silently pass (regenerate-and-assert-clean means "the copy exists and
# equals generator output").
if [ ! -f "$COPY" ]; then
  echo "dedup-hash fence: DRIFT — copy missing at $COPY." >&2
  echo "Regenerate it from the canonical source: node $GENERATOR" >&2
  exit 1
fi

# Regenerate from the canonical source to STDOUT (git-state-independent) and diff against the
# on-disk copy. Any difference is drift.
if node "$GENERATOR" --source "$SOURCE" --stdout | diff -u - "$COPY"; then
  echo "dedup-hash fence: $COPY IS current generator output (no drift)."
  exit 0
else
  echo "" >&2
  echo "dedup-hash fence: DRIFT — $COPY is not the current output of $GENERATOR from $SOURCE." >&2
  echo "The canonical import_hash source and its generated copy have diverged (SELF-204 /" >&2
  echo "ADR-034 D4). Do NOT hand-edit the copy. Fix at source:" >&2
  echo "  1. Edit the canonical source: $SOURCE" >&2
  echo "  2. Regenerate: node $GENERATOR" >&2
  echo "  3. Commit the regenerated copy." >&2
  exit 1
fi
