#!/usr/bin/env bash
#
# db-template-clone.sh — fast scratch-DB clone from the `pfin_tmpl` template,
# DevOps-owned, per F/CTO-ratified loop-mechanics option A (2026-09-02
# sitting). Companion to scripts/db-template-build.sh.
#
# WHAT THIS REPLACES
#   QA/Architect's sequential 001..0NN migration apply for a throwaway
#   verification DB (see the "full chain" / "for migration verify" recipes
#   under .claude/agent-memory/{architect,qa}/) — this clones the pre-built
#   `pfin_tmpl` template instead, seconds instead of a full sequential apply.
#
# THE STALENESS FENCE — read this before trusting a clone
#   `pfin_tmpl` is built once by db-template-build.sh and only refreshed when
#   something re-runs it (see .husky/post-merge and docs/db-template.md for
#   the trigger). If the migrations tree has moved since the template was
#   last built, a naive `createdb --template=pfin_tmpl` would silently hand
#   back an OUT-OF-DATE schema with no error — exactly the failure mode this
#   tool exists to prevent.
#
#   So: before cloning, this script reads the marker `pfin_tmpl` was stamped
#   with at build time (public._template_meta: head_migration filename +
#   sha256 of the full migrations tree) and compares BOTH against the
#   CURRENT tree. Any mismatch — including one caused by editing an
#   already-numbered migration file without adding a new one, which a
#   filename-only check would miss — REFUSES to clone and tells you to run
#   `scripts/db-template-build.sh`. It never serves a stale schema quietly.
#
# THE OTHER GAP THIS CLOSES — pg_db_role_setting
#   `CREATE DATABASE ... TEMPLATE` does not copy `pg_db_role_setting` (a
#   shared catalog keyed by database OID; a clone gets a new OID and no row
#   at all). Migration 061's `ALTER DATABASE current_database() SET
#   TimeZone = 'UTC'` is exactly this kind of setting — QA measured a
#   template clone silently losing it 2026-08-19 (085). Rather than
#   hardcoding "replay the TimeZone setting", this script reads EVERY
#   database-level (`setrole = 0`) row `pfin_tmpl` itself carries and replays
#   each one onto the clone — so a future migration adding another
#   `ALTER DATABASE ... SET` is covered automatically, with no edit needed
#   here.
#
# WHAT THIS DOES NOT COVER
#   - Role-level GUC overrides (`ALTER ROLE ... SET`, `setrole <> 0`) are
#     CLUSTER-level, not per-database, and already shared by every database
#     on this cluster including the clone — nothing to replay.
#   - This is LOCAL/CI throwaway tooling. It has no opinion on Coolify or
#     production.
#   - Per QA's own scratch-DB discipline: the clone is disposable per
#     SESSION, not per query — don't leave ad hoc committed rows in it across
#     unrelated verification runs; drop and re-clone instead.
#
# USAGE
#   scripts/db-template-clone.sh <scratch-db-name>
#
# EXIT CODES
#   0  cloned successfully
#   1  no usable template, or the template is stale — nothing was cloned

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_HOST="${DB_TEMPLATE_HOST:-127.0.0.1}"
DB_PORT="${DB_TEMPLATE_PORT:-54322}"
SUPERUSER="${DB_TEMPLATE_SUPERUSER:-postgres}"
TEMPLATE_NAME="${DB_TEMPLATE_NAME:-pfin_tmpl}"
MIGRATIONS_DIR="supabase/migrations"
export PGPASSWORD="${DB_TEMPLATE_PASSWORD:-postgres}"

log() { echo "[db-template-clone] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

SCRATCH_NAME="${1:-}"
[ -n "$SCRATCH_NAME" ] || die "usage: $0 <scratch-db-name>"
[ -d "$MIGRATIONS_DIR" ] || die "no $MIGRATIONS_DIR found — run from the repo root (or a worktree of it)."

psql_as() {
  local dbname="$1"; shift
  psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$dbname" -v ON_ERROR_STOP=1 "$@"
}

# --- does the template even exist? ---
TEMPLATE_EXISTS=$(psql_as postgres -Atqc "select 1 from pg_database where datname = '$TEMPLATE_NAME';" 2>/dev/null || true)
[ "$TEMPLATE_EXISTS" = "1" ] || die "no '$TEMPLATE_NAME' template found. Run scripts/db-template-build.sh first (it does not run automatically on every check-out — see docs/db-template.md)."

# --- staleness fence: compare the template's marker to the CURRENT tree ---
MARKER=$(psql_as "$TEMPLATE_NAME" -Atqc "select head_migration || '|' || content_sha256 from public._template_meta;" 2>/dev/null || true)
[ -n "$MARKER" ] || die "'$TEMPLATE_NAME' exists but carries no public._template_meta marker — it did not come from db-template-build.sh, or was built by an older version of it. Rebuild: scripts/db-template-build.sh."

TEMPLATE_HEAD="${MARKER%%|*}"
TEMPLATE_SHA="${MARKER##*|}"

CURRENT_HEAD=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \; | sort | tail -n1)
CURRENT_SHA=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z | xargs -0 cat | shasum -a 256 | awk '{print $1}')

if [ "$TEMPLATE_HEAD" != "$CURRENT_HEAD" ] || [ "$TEMPLATE_SHA" != "$CURRENT_SHA" ]; then
  die "'$TEMPLATE_NAME' is STALE — refusing to clone.
    template:  head=$TEMPLATE_HEAD  sha256=$TEMPLATE_SHA
    tree now:  head=$CURRENT_HEAD  sha256=$CURRENT_SHA
  Run scripts/db-template-build.sh to refresh, then retry."
fi
log "staleness check passed (head=$CURRENT_HEAD, sha256=$CURRENT_SHA)."

# --- the fast path: template clone ---
psql_as postgres -Atqc "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$SCRATCH_NAME' and pid <> pg_backend_pid();" >/dev/null 2>&1 || true
psql_as postgres -Atqc "drop database if exists \"$SCRATCH_NAME\";" >/dev/null
createdb -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" --template="$TEMPLATE_NAME" "$SCRATCH_NAME"
log "cloned $TEMPLATE_NAME -> $SCRATCH_NAME."

# --- replay pg_db_role_setting (setrole = 0, i.e. ALTER DATABASE ... SET) ---
# generically: whatever the template carries, not hardcoded to TimeZone. See
# header. `setconfig` entries look like "TimeZone=UTC" / "key=value"; split
# on the FIRST '=' only (a value could itself contain '=', e.g. a DSN).
SETTINGS=$(psql_as postgres -Atqc "
  select unnest(drs.setconfig)
    from pg_db_role_setting drs
    join pg_database d on d.oid = drs.setdatabase
   where d.datname = '$TEMPLATE_NAME'
     and drs.setrole = 0;
" 2>/dev/null || true)

if [ -n "$SETTINGS" ]; then
  while IFS= read -r kv; do
    [ -z "$kv" ] && continue
    key="${kv%%=*}"
    val="${kv#*=}"
    log "replaying per-database setting onto clone: $key"
    psql_as postgres -v ON_ERROR_STOP=1 -c "alter database \"$SCRATCH_NAME\" set \"$key\" = '$val';" >/dev/null
  done <<< "$SETTINGS"
else
  log "template carries no database-level (setrole=0) pg_db_role_setting entries — nothing to replay."
fi

log "done. $SCRATCH_NAME is ready (head=$CURRENT_HEAD)."
