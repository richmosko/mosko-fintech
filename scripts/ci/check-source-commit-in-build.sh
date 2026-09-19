#!/usr/bin/env bash
#
# check-source-commit-in-build.sh — offline-strikeable predicate for the
# "Source commit availability" gate (docs/deployment-runbook.md §4, added
# 2026-09-17 as ADR-072 Amendment 6, PR #794). scripts/provision-migrator-app.sh
# and scripts/provision-supabase-stack.sh both call this on EVERY run
# (preflight and --apply) against a `GET /api/v1/applications/<uuid>`
# response, to assert `settings.include_source_commit_in_build == true`
# BEFORE triggering a deploy.
#
# WHY THIS EXISTS AS A SEPARATE SCRIPT (mirrors
# scripts/ci/check-migrator-names-absent.sh's own extraction rationale,
# ADR-072 Amendment 4 / PR #819): the predicate itself -- "does this
# application JSON's settings object carry include_source_commit_in_build
# as the literal boolean true" -- needs no live Coolify resource to
# exercise. It is exactly as strikeable OFFLINE, against a fixture file
# shaped like a real `GET /applications/<uuid>` response, as it is against
# a live box. Both provisioning scripts pipe their live GET response
# through this same file, so a fix to the predicate here is a fix
# everywhere it runs.
#
# MEASURED, 2026-09-19: scripts/provision-migrator-app.sh --apply created
# `pfin-migrator` and its FIRST deploy FATALed at the migrator Dockerfile's
# GIT_SHA/SOURCE_COMMIT build-arg guard, because the application was
# created with include_source_commit_in_build=false (the runbook's §4 note
# was, until this predicate existed, a BY-HAND UI step with no scripted
# assertion -- see docs/deployment-runbook.md §4 for the full field-name /
# UI-location provenance this predicate assumes).
#
# The `settings.include_source_commit_in_build` JSON path this script reads
# was, before this date, source-verified only (traced to the Livewire
# backing field, not observed live). Sec's live read-back on this same day,
# on `GET /api/v1/applications/anz4uzfdumcfgc92wnfpov4i` (Coolify 4.3.18),
# MEASURED it directly: `false` before team-lead's PATCH, `true` after, at
# exactly this path -- the basis for this predicate is now a live
# measurement, not only a source trace.
#
# WHAT THIS SCRIPT DOES NOT COVER, stated so it is not oversold: whether a
# PATCH actually lands and is re-readable on a real Coolify instance is an
# end-to-end property of a live box; this script only judges JSON it is
# handed. The provisioning scripts' own PATCH-then-re-read-then-die loop is
# what proves the live end-to-end case -- this predicate is what both of
# them call on every read along that loop.
#
# Usage:
#   check-source-commit-in-build.sh [<application-json-file>]   # reads stdin if omitted
#
# Input shape: the JSON body `GET /api/v1/applications/<uuid>` returns (a
# top-level object with a nested `settings` object). A bare
# `{"settings": {"include_source_commit_in_build": true}}` also works --
# only that one path is read.
#
# Exit codes:
#   0 — settings.include_source_commit_in_build is the literal boolean true.
#   1 — present but not true (false, or any other value) -- field named on
#       stderr, value never printed (it is not a secret, but the value
#       itself is never the useful part of this message).
#   2 — no input, unparseable JSON, or settings.include_source_commit_in_build
#       missing entirely -- cannot confirm true over nothing to check; fail
#       closed rather than pass by default.

set -euo pipefail

INPUT="${1:-/dev/stdin}"

RAW="$(cat "$INPUT" 2>/dev/null || true)"
if [[ -z "$RAW" ]]; then
  echo "FATAL: no input -- cannot confirm settings.include_source_commit_in_build over an empty response. Failing closed." >&2
  exit 2
fi

RESULT="$(printf '%s' "$RAW" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as exc:
    print("UNPARSEABLE: %s" % exc)
    sys.exit(0)
settings = d.get("settings") if isinstance(d, dict) else None
if not isinstance(settings, dict) or "include_source_commit_in_build" not in settings:
    print("MISSING")
    sys.exit(0)
value = settings["include_source_commit_in_build"]
if value is True:
    print("TRUE")
else:
    print("FALSE: %r" % (value,))
')"

case "$RESULT" in
  TRUE)
    echo "OK: settings.include_source_commit_in_build is true."
    exit 0
    ;;
  FALSE:*)
    echo "FAIL: settings.include_source_commit_in_build is ${RESULT#FALSE: } -- not the literal boolean true. Build will FATAL at the migrator Dockerfile's GIT_SHA/SOURCE_COMMIT guard (see docs/deployment-runbook.md §4)." >&2
    exit 1
    ;;
  MISSING)
    echo "FATAL: settings.include_source_commit_in_build is absent from this response -- cannot confirm true over a missing field. Failing closed." >&2
    exit 2
    ;;
  UNPARSEABLE:*)
    echo "FATAL: input is not valid JSON (${RESULT#UNPARSEABLE: }). Failing closed." >&2
    exit 2
    ;;
  *)
    echo "FATAL: unrecognized internal result '$RESULT' -- failing closed." >&2
    exit 2
    ;;
esac
