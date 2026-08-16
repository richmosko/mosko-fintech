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
#   directory OUTSIDE this repo, and prunes to the newest $KEEP snapshots
#   (subject to the shrink guard below).
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
#   ⚠ UNDOCUMENTED DEPENDENCY (Sec F3): dump COMPLETENESS for RLS-protected
#   pfin.* tables rests on the connecting role ($DB_SUPERUSER, default
#   'postgres') retaining a way past RLS — currently true for TWO independent
#   reasons, both measured: 'postgres' has rolbypassrls=t, AND it owns every
#   pfin.* table (and relforcerowsecurity=f, so ownership alone would suffice
#   even without BYPASSRLS). If either the role's BYPASSRLS attribute is
#   revoked or table ownership moves off 'postgres' in a future hardening
#   pass, pg_dump does NOT error — it silently runs the dump as a normal RLS-
#   restricted SELECT and the resulting file has fewer rows than reality, with
#   no signal in this script that anything is wrong (byte size alone won't
#   reliably catch a partial per-table omission the way it catches a
#   whole-database wipe). Re-run the BYPASSRLS/ownership check above after any
#   change to pfin.* ownership or the local dev role grants.
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
#   - The RLS-completeness dependency immediately above: byte-size guards catch
#     "the whole database emptied out," not "one table's rows silently missing
#     because the connecting role lost its RLS bypass."
#
# RETENTION AND THE SHRINK GUARD (Sec B1 — blocking fix)
#   Keeps the newest $KEEP snapshots in $SNAPSHOT_DIR, pruned on every
#   successful run — UNLESS the shrink guard below fires. Location is a
#   sibling of the repo tree (matching the docs/records/2026-08-14-db-reset-
#   incident.md recovery-asset convention of ~/Projects/mosko-fintech-
#   recovery/), not inside any git worktree — multiple worktrees for
#   different agents should not fragment snapshots across per-worktree
#   gitignored directories, and a fixed absolute path avoids that.
#
#   The incident scenario this guards against: an unscoped reset (or any of
#   the sibling destructive routes above) runs, THEN this script runs (next
#   session start) and dumps the now-near-empty database as a normal,
#   successful pg_dump — a small-but-valid file that recency-only pruning
#   would treat as just the newest snapshot, aging out and deleting the large
#   PRE-incident ones over the next $KEEP runs. Ten sessions later, every
#   recovery point is the wiped state.
#
#   Two independent guards, both measured against this repo's real dump sizes
#   (a schema-only, zero-data dump of this DB's actual schema is ~911KB; a
#   dump of a genuinely empty database — no pfin/auth objects at all — is
#   ~900 BYTES; the full populated local dev dump used to build this script
#   was ~1.4MB):
#     1. PROMOTION FLOOR ($PROMOTION_FLOOR_BYTES, default 200000 = ~200KB —
#        comfortably below the ~911KB "real schema, zero rows" floor and
#        comfortably above the ~900B "no schema at all" case, so it only
#        trips on a truncated/corrupt/wrong-target dump, not a legitimately
#        row-less one). Below this, the dump is NOT promoted to a snapshot at
#        all — logged loudly, existing snapshots untouched, as if the run had
#        failed.
#     2. SHRINK-VS-RETAINED GUARD (Sec's number: new < 0.5x the largest
#        PREVIOUSLY-retained snapshot). This one DOES promote the new dump —
#        it's a real, complete pg_dump of current truth, which is itself
#        worth keeping — but SKIPS PRUNING ENTIRELY for this run, so older
#        (possibly pre-incident, larger) snapshots are not rotated away in
#        favour of a run of small ones. Logged loudly either way.
#
# STALENESS WARNING (Sec F1)
#   Every skip path (no docker, no container, connection not ready, pg_dump
#   failure) checks whether a usable recovery point still exists: if there has
#   NEVER been a snapshot, or the newest one is older than
#   $STALE_THRESHOLD_SECONDS (default 24h), a distinctly-marked WARNING is
#   logged. Silence on a skip is the compound risk this closes — the script
#   still never blocks its caller, it just stops being quiet about it.
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
# PERMISSIONS (Sec B2 — blocking fix)
#   Snapshots are full-database dumps, including auth schema credential
#   material (password hashes etc.), unencrypted. `umask 077` is set before
#   ANY file or directory this script creates, and $SNAPSHOT_DIR is explicitly
#   chmod 700'd on every run (mkdir -p alone won't tighten a directory that
#   already exists at a looser mode from before this fix landed).
#
# This script NEVER blocks its caller. Every exit path is 0 — a broken docker
# CLI, an unreachable stack, a container name mismatch, an implausibly-small
# dump, or a failed pg_dump degrades to "no snapshot taken this run," logged
# loudly to stderr, never a session-start failure. That is a deliberate trade
# for a hook that must never be the reason a session won't start; it means a
# silent-looking failure here is possible and this script's stderr (or
# /tmp/db-snapshot-hook.log, see the SessionStart wiring) is where it shows —
# which is exactly what the F1 staleness warning exists to surface.

set -uo pipefail
umask 077

SNAPSHOT_DIR="${DB_SNAPSHOT_DIR:-$HOME/Projects/mosko-fintech-db-snapshots}"
KEEP_RAW="${DB_SNAPSHOT_KEEP:-10}"
DEBOUNCE_SECONDS="${DB_SNAPSHOT_DEBOUNCE_SECONDS:-900}"          # 15 min
STALE_THRESHOLD_SECONDS="${DB_SNAPSHOT_STALE_SECONDS:-86400}"    # 24h
PROMOTION_FLOOR_BYTES="${DB_SNAPSHOT_FLOOR_BYTES:-200000}"       # ~200KB, see header rationale
DB_HOST="${DB_SNAPSHOT_HOST:-127.0.0.1}"
DB_PORT="${DB_SNAPSHOT_PORT:-54322}"
DB_NAME="${DB_SNAPSHOT_DBNAME:-postgres}"
DB_SUPERUSER="${DB_SNAPSHOT_USER:-postgres}"

log() { echo "[db-snapshot] $*" >&2; }
filesize() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

# F2 — validate DB_SNAPSHOT_KEEP. An invalid value (0, negative, non-numeric)
# previously reached `tail -n +$((KEEP+1))` as `tail -n +1` or worse, which
# deletes EVERY snapshot including the one just written this run.
if [[ "$KEEP_RAW" =~ ^[1-9][0-9]*$ ]]; then
  KEEP="$KEEP_RAW"
else
  KEEP=10
  log "DB_SNAPSHOT_KEEP='$KEEP_RAW' is not a positive integer — defaulting to 10."
fi

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || { log "cannot create $SNAPSHOT_DIR — skipping."; exit 0; }
chmod 700 "$SNAPSHOT_DIR" 2>/dev/null || true   # tighten even if the dir pre-dates this fix (B2)

# Computed once, up front, so every skip path below can check staleness (F1)
# without re-deriving it.
LATEST=$(ls -t "$SNAPSHOT_DIR"/db-snapshot-*.dump 2>/dev/null | head -n1 || true)
AGE_OF_LATEST=0
if [ -n "$LATEST" ]; then
  MTIME=$(stat -f %m "$LATEST" 2>/dev/null || stat -c %Y "$LATEST" 2>/dev/null || echo 0)
  AGE_OF_LATEST=$(( $(date +%s) - MTIME ))
fi

warn_if_stale() {
  if [ -z "$LATEST" ]; then
    log "WARNING: no DB snapshot has ever been taken (checked $SNAPSHOT_DIR) — no local recovery point exists right now."
  elif [ "$AGE_OF_LATEST" -gt "$STALE_THRESHOLD_SECONDS" ]; then
    log "WARNING: newest snapshot is $((AGE_OF_LATEST / 3600))h old (> 24h threshold) and this run could not refresh it — recovery point is stale."
  fi
}

command -v docker >/dev/null 2>&1 || { log "docker not on PATH — skipping."; warn_if_stale; exit 0; }

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
  warn_if_stale
  exit 0
fi

# Reachability probe inside the container — cheap, and confirms the server is
# actually accepting connections, not just that the container process is up.
if ! docker exec "$CONTAINER" psql -U "$DB_SUPERUSER" -d "$DB_NAME" -Atqc 'select 1' >/dev/null 2>&1; then
  log "Postgres in $CONTAINER not accepting connections yet — skipping."
  warn_if_stale
  exit 0
fi

if [ "$FORCE" -ne 1 ] && [ -n "$LATEST" ] && [ "$AGE_OF_LATEST" -lt "$DEBOUNCE_SECONDS" ]; then
  log "recent snapshot is ${AGE_OF_LATEST}s old (< ${DEBOUNCE_SECONDS}s) — skipping; use --force to override."
  exit 0   # a fresh-enough snapshot exists by definition — no staleness warning needed
fi

# Largest PRE-EXISTING retained snapshot, captured before this run's dump is
# promoted, so the shrink guard compares against history, not itself.
MAX_EXISTING_SIZE=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  sz=$(filesize "$f")
  [ "$sz" -gt "$MAX_EXISTING_SIZE" ] && MAX_EXISTING_SIZE="$sz"
done < <(ls "$SNAPSHOT_DIR"/db-snapshot-*.dump 2>/dev/null || true)

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$SNAPSHOT_DIR/db-snapshot-$STAMP.dump"
TMP="$OUT.partial"
ERRLOG="$SNAPSHOT_DIR/.last-pg_dump-stderr.log"

if docker exec "$CONTAINER" pg_dump -U "$DB_SUPERUSER" -d "$DB_NAME" -Fc >"$TMP" 2>"$ERRLOG"; then
  NEWSIZE=$(filesize "$TMP")

  # Promotion floor (Sec B1, part 2).
  if [ "$NEWSIZE" -lt "$PROMOTION_FLOOR_BYTES" ]; then
    rm -f "$TMP"
    log "WARNING: pg_dump produced an implausibly small file (${NEWSIZE} bytes < ${PROMOTION_FLOOR_BYTES}-byte floor) — refusing to promote it as a snapshot. Nothing written; existing snapshots untouched."
    warn_if_stale
    exit 0
  fi

  mv "$TMP" "$OUT"
  log "wrote $OUT (${NEWSIZE} bytes, container=$CONTAINER)"

  # Shrink-vs-retained guard (Sec B1, part 1): new < 0.5x the largest
  # pre-existing retained snapshot -> skip pruning this run.
  SKIP_PRUNE=0
  if [ "$MAX_EXISTING_SIZE" -gt 0 ] && [ "$((NEWSIZE * 2))" -lt "$MAX_EXISTING_SIZE" ]; then
    SKIP_PRUNE=1
    log "WARNING: new snapshot (${NEWSIZE}B) is under half the largest retained snapshot (${MAX_EXISTING_SIZE}B) — SKIPPING PRUNING this run so an older, larger (possibly pre-incident) snapshot is not rotated away. Investigate before relying on retention alone."
  fi
else
  rm -f "$TMP"
  log "pg_dump failed — see $ERRLOG — skipping (not blocking)."
  warn_if_stale
  exit 0
fi

# Retention: keep the newest $KEEP, prune the rest — unless the shrink guard
# fired above.
if [ "$SKIP_PRUNE" -eq 0 ]; then
  ls -t "$SNAPSHOT_DIR"/db-snapshot-*.dump 2>/dev/null | tail -n "+$((KEEP + 1))" | while IFS= read -r old; do
    rm -f -- "$old"
  done
fi

exit 0
