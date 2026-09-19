#!/usr/bin/env bash
#
# check-migrator-names-absent.sh — offline-strikeable predicate for
# ADR-072 Amendment 4 / BACKLOG.md §7.36 item 29's post-move absence
# assertion (Sec condition: "the strike-proven post-move assertion that
# the shared store contains NEITHER MIGRATOR_DB_PASSWORD NOR
# MIGRATOR_DB_USER").
#
# Reads raw `env`-shaped output (`KEY=VALUE`, one per line — exactly what
# `docker compose ... exec -T <container> env` prints) from a file
# argument or STDIN, and fails closed if `MIGRATOR_DB_USER` or
# `MIGRATOR_DB_PASSWORD` is PRESENT AS A NAME — regardless of value. A
# blanked value (`MIGRATOR_DB_USER=`) still carries the name and still
# FAILS this check; only an ABSENT name (no line at all) passes.
#
# WHY THIS IS A SEPARATE SCRIPT, EXTRACTED FROM
# scripts/provision-supabase-stack.sh (Sec joint review, PR #819,
# 2026-09-18): the NAME-vs-VALUE predicate itself — "does this env dump
# contain a line whose key is one of these two names" — needs no live
# Coolify resource to exercise. It is exactly as strikeable OFFLINE as the
# sibling fence's own goldens, against a fixture file shaped like a real
# `env` dump, rather than only against a live box. Extracting it here
# means the predicate has its own committed, CI-run strike-proof
# (tests/fixtures/ci/migrator-names-absent-*.env, wired in
# security-scan.yml's fence-migrator-bind job) — the thing that was
# previously deferred, whole, to a live-Coolify-only runbook step.
#
# What THIS script's strike-proof does NOT cover, stated so it is not
# oversold: whether the box's ACTUAL env store, after a real cutover, is
# clean — that is an end-to-end property of a live Coolify resource and
# this script cannot manufacture that evidence from a fixture. That
# end-to-end strike (re-add a name to the LIVE store, confirm this
# predicate goes RED against the real box, remove it, confirm GREEN again)
# stays at docs/deployment-runbook.md §6.8 CUTOVER PROCEDURE step 10 — this
# script is what BOTH that live step and this repo's CI invoke, so a fix
# to the predicate here is a fix everywhere it runs.
#
# Usage:
#   check-migrator-names-absent.sh [<env-dump-file>]   # reads stdin if omitted
#
# Exit codes:
#   0 — neither MIGRATOR_DB_USER nor MIGRATOR_DB_PASSWORD present as a name.
#   1 — one or both present (offender(s) named on stderr; never the value).
#   2 — no input at all (empty stdin/file) — cannot confirm absence over
#       nothing to check; fail closed rather than pass by default.

set -euo pipefail

INPUT="${1:-/dev/stdin}"

RAW="$(cat "$INPUT" 2>/dev/null || true)"
if [[ -z "$RAW" ]]; then
  echo "FATAL: no input -- cannot confirm MIGRATOR_DB_* absence over an empty env dump. Failing closed." >&2
  exit 2
fi

NAMES="$(printf '%s\n' "$RAW" | cut -d= -f1 | sort -u)"

OFFENDERS=""
for offender in MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD; do
  if printf '%s\n' "$NAMES" | grep -qx "$offender"; then
    OFFENDERS="$OFFENDERS $offender"
  fi
done

if [[ -n "$OFFENDERS" ]]; then
  echo "FAIL:$OFFENDERS present -- a blanked value does not pass this check, only a deleted name does." >&2
  exit 1
fi

echo "OK: MIGRATOR_DB_USER and MIGRATOR_DB_PASSWORD both absent (checked by name, not value)."
exit 0
