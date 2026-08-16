#!/usr/bin/env bash
#
# db-snapshot.sh — best-effort pg_dump of the local Supabase Postgres, DevOps-owned.
#
# WHY THIS EXISTS
#   Sec's recommendation (C) from the PR #463 review of the db-reset permission
#   guard (docs/records/2026-08-14-db-reset-incident.md): "pre-flight pg_dump
#   snapshot — protection independent of guessing invocation form." The guard in
#   .claude/settings.json denies the ONE command string the 2026-08-14 incident
#   used ('supabase db reset', any flags). It does NOT and cannot cover every
#   route to the same data loss — 'supabase stop --no-backup', 'docker compose
#   down -v' / 'docker volume rm', a raw 'psql ... drop schema pfin cascade' all
#   reach the identical outcome and none of them share a command-string shape
#   with each other, let alone with 'db reset'. Enumerating more banned strings
#   just repeats the H1/H2 chase from PR #463 (interposed flags, prefixes,
#   compound commands) against an open-ended set of destructive verbs. This
#   script sidesteps that chase entirely: instead of trying to recognize every
#   way the data could be destroyed, it guarantees a recent recovery point
#   exists BEFORE any of them run, wired via SessionStart (see .claude/settings.json)
#   so it fires regardless of which destructive command a session later uses.
#
# WHAT IT DOES
#   pg_dump's the full local Postgres database (every schema — pfin, auth,
#   storage, etc. — a strict superset of "pfin + relevant auth rows") in custom
#   format (-Fc: compressed, selectively restorable via pg_restore) to a
#   directory OUTSIDE this repo, and prunes to the newest $KEEP snapshots.
#
#   Runs pg_dump INSIDE the local Supabase Postgres container via `docker exec`
#   rather than a host-installed pg_dump. Measured, not assumed: this machine's
#   Homebrew pg_dump is 14.23 against a supabase/postgres:17.6 server, and
#   pg_dump refuses cross-major-version dumps outright ("server version
#   mismatch") — a host-pg_dump design would have failed on the very first
#   real run on the very machine this was built on. The container ships a
#   version-matched pg_dump; docker exec ... pg_dump ... streamed to stdout
#   avoids the host/server version-skew class entirely and needs nothing
#   installed on the host beyond docker and the running stack.
#
#   Deliberately NOT --schema-only (would drop every row — the exact thing worth
#   recovering) and NOT --no-privileges (drops REVOKEs; this repo's RLS/DEFINER
#   posture depends on them — a dump that silently drops privileges is a
#   downgrade, not a backup). Default pg_dump flags keep schema + data +
#   GRANT/REVOKE.
#
#   Roles (CREATE ROLE, e.g. pfin_etl's NOLOGIN posture) are NOT captured — that
#   is cluster state, not database state, pg_dump is inherently per-database,
#   and the 2026-08-14 incident did not touch it (nav_daily's ADR-053 role
#   posture survived that reset; see the incident record's "Survived" line).
#   A cluster-level 'pg_dumpall --roles-only' is out of scope for this pass.
#
# WHAT IT DOES NOT COVER (state this in the PR, don't let it read as complete)
#   - Mid-session drift: this runs once at SessionStart (see hook wiring below)
#     plus a debounce window, so a destructive command run late in a long
#     session may be many minutes newer than the last snapshot. Run this script
#     by hand with --force immediately before anything you know is destructive
#     (supabase stop --no-backup, docker compose down -v, a manual DROP) to
#     close that gap for a specific operation.
#   - This is LOCAL dev only. It has no opinion on Coolify/production — those
#     are a different backup surface entirely and out of scope here.
#   - If the container itself is removed/destroyed (not just stopped) before
#     this ever runs, or docker isn't running at SessionStart, there is nothing
#     to dump from — this is a snapshot of live state, not a substitute for
#     git-tracked migrations.
#
# RETENTION
#   Keeps the newest $KEEP snapshots in $SNAPSHOT_DIR, prunes older ones on
#   every successful run. Location is a sibling of the repo tree (matching the
#   docs/records/2026-08-14-db-reset-incident.md recovery-asset convention of
#   ~/Projects/mosko-fintech-recovery/), not inside any git worktree — multiple
#   worktrees for different agents should not fragment snapshots across
#   per-worktree gitignored directories, and a fixed absolute path avoids that.
#
# USAGE
#   scripts/db-snapshot.sh            # normal run — debounced, silent skip if
#                                      # no local stack is up (CI, container-only
#                                      # subagent sessions, etc.)
#   scripts/db-snapshot.sh --force    # bypass the debounce window; use right
#                                      # before a known-destructive operation
#
# RESTORE (manual, deliberately not scripted — see PR body: an automated
# restore path is itself a destructive-invocation risk that would need its own
# guard, and restores are rare enough to want a human reading the dump list)
#   ⚠ MEASURED: restore as 'postgres' produces 147 spurious errors (ownership /
#   default-privilege ALTERs) because 'postgres' is NOT the real superuser in
#   this stack — 'supabase_admin' is (rolsuper=t; 'postgres' is rolsuper=f).
#   Restoring as 'postgres' still lands all DATA correctly (verified: identical
#   row counts across pfin.* and auth.users) but is noisy. Restore as
#   supabase_admin for a clean, error-free run:
#     docker exec <container> psql -U supabase_admin -d postgres \
#       -c "create database scratch_restore_check"
#     docker cp <snapshot>.dump <container>:/tmp/restore.dump
#     docker exec <container> pg_restore -U supabase_admin \
#       -d scratch_restore_check /tmp/restore.dump
#   (container name: see CONTAINER derivation below, typically
#   supabase_db_mosko-fintech)
#
# This script NEVER blocks its caller. Every exit path is 0 — a broken docker
# CLI, an unreachable stack, a container name mismatch, or a failed pg_dump
# degrades to "no snapshot taken this run," logged to stderr, never a
# session-start failure. That is a deliberate trade for a hook that must never
# be the reason a session won't start; it means a silent failure here is
# possible and this script's stderr (or /tmp/db-snapshot-hook.log, see the
# SessionStart wiring) is where it shows.

set -uo pipefail

SNAPSHOT_DIR="${DB_SNAPSHOT_DIR:-$HOME/Projects/mosko-fintech-db-snapshots}"
KEEP="${DB_SNAPSHOT_KEEP:-10}"
DEBOUNCE_SECONDS="${DB_SNAPSHOT_DEBOUNCE_SECONDS:-900}"   # 15 min
DB_HOST="${DB_SNAPSHOT_HOST:-127.0.0.1}"
DB_PORT="${DB_SNAPSHOT_PORT:-54322}"
DB_NAME="${DB_SNAPSHOT_DBNAME:-postgres}"
DB_SUPERUSER="${DB_SNAPSHOT_USER:-postgres}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

log() { echo "[db-snapshot] $*" >&2; }

command -v docker >/dev/null 2>&1 || { log "docker not on PATH — skipping."; exit 0; }

mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || { log "cannot create $SNAPSHOT_DIR — skipping."; exit 0; }

# Container name follows the Supabase CLI's own convention: supabase_db_<project_id>.
# project_id is read live from supabase/config.toml (fixed at "mosko-fintech" as
# of this writing) rather than hardcoded, so a future project_id change doesn't
# silently break this. Falls back to a docker ps pattern match if config.toml
# is unreadable from wherever this script is invoked.
PROJECT_ID=""
if [ -f "supabase/config.toml" ]; then
  PROJECT_ID=$(grep -m1 -E '^project_id' supabase/config.toml | sed -E 's/^project_id[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
fi
if [ -n "$PROJECT_ID" ]; then
  CONTAINER="supabase_db_${PROJECT_ID}"
else
  CONTAINER=$(docker ps --filter "name=supabase_db_" --format '{{.Names}}' 2>/dev/null | head -n1)
fi

if [ -z "${CONTAINER:-}" ] || [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
  log "local Supabase Postgres container not running (looked for '${CONTAINER:-supabase_db_*}') — skipping."
  exit 0
fi

# Reachability probe inside the container — cheap, and confirms the server is
# actually accepting connections, not just that the container process is up.
if ! docker exec "$CONTAINER" psql -U "$DB_SUPERUSER" -d "$DB_NAME" -Atqc 'select 1' >/dev/null 2>&1; then
  log "Postgres in $CONTAINER not accepting connections yet — skipping."
  exit 0
fi

LATEST=$(ls -t "$SNAPSHOT_DIR"/db-snapshot-*.dump 2>/dev/null | head -n1 || true)
if [ "$FORCE" -ne 1 ] && [ -n "$LATEST" ]; then
  MTIME=$(stat -f %m "$LATEST" 2>/dev/null || stat -c %Y "$LATEST" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$((NOW - MTIME))
  if [ "$AGE" -lt "$DEBOUNCE_SECONDS" ]; then
    log "recent snapshot is ${AGE}s old (< ${DEBOUNCE_SECONDS}s) — skipping; use --force to override."
    exit 0
  fi
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$SNAPSHOT_DIR/db-snapshot-$STAMP.dump"
TMP="$OUT.partial"
ERRLOG="$SNAPSHOT_DIR/.last-pg_dump-stderr.log"

if docker exec "$CONTAINER" pg_dump -U "$DB_SUPERUSER" -d "$DB_NAME" -Fc >"$TMP" 2>"$ERRLOG"; then
  mv "$TMP" "$OUT"
  log "wrote $OUT"
else
  rm -f "$TMP"
  log "pg_dump failed — see $ERRLOG — skipping (not blocking)."
  exit 0
fi

# Retention: keep the newest $KEEP, prune the rest.
ls -t "$SNAPSHOT_DIR"/db-snapshot-*.dump 2>/dev/null | tail -n "+$((KEEP + 1))" | while IFS= read -r old; do
  rm -f -- "$old"
done

exit 0
