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
#   with at build time (public._template_meta: head_migration filename,
#   sha256 of the full migrations tree, and the container image id the
#   template's auth/extensions/vault schema was dumped from) and compares
#   ALL THREE against the current state. Any mismatch — including one caused
#   by editing an already-numbered migration file without adding a new one
#   (which a filename-only check would miss), or a CLI/image upgrade that
#   changes the auth schema with zero change to the migrations tree (which
#   neither migration-tree leg can see) — REFUSES to clone and tells you to
#   run `scripts/db-template-build.sh`. It never serves a stale schema
#   quietly.
#
# THE OTHER GAP THIS CLOSES — pg_db_role_setting
#   `CREATE DATABASE ... TEMPLATE` does not copy `pg_db_role_setting` (a
#   shared catalog keyed by database OID; a clone gets a new OID and no row
#   at all). Migration 061's `ALTER DATABASE current_database() SET
#   TimeZone = 'UTC'` is exactly this kind of setting — QA measured a
#   template clone silently losing it 2026-08-19 (085). Rather than
#   hardcoding "replay the TimeZone setting", this script reads EVERY row
#   `pfin_tmpl` carries that is keyed to ITS OWN database OID and replays
#   each one onto the clone — so a future migration adding another
#   `ALTER DATABASE ... SET` (or `ALTER ROLE ... IN DATABASE ... SET`, see
#   below) is covered automatically, with no edit needed here.
#
#   TWO shapes are keyed to a specific database this way, not just one:
#     - `ALTER DATABASE d SET k=v`            -> setrole = 0, setdatabase = d
#     - `ALTER ROLE r IN DATABASE d SET k=v`   -> setrole = r, setdatabase = d
#   An EARLIER version of this script (and its docs) claimed the second
#   shape was cluster-level and "already shared by every database" —
#   **FALSE, Sec-caught (2026-09-02):** `setdatabase` pins it to THIS
#   database exactly like the first shape, so it is exactly as invisible to
#   a template clone. Zero such rows exist on `pfin_tmpl` as of this
#   writing (verified by direct query against `pg_db_role_setting`,
#   2026-09-02), but the query below covers both shapes generically rather
#   than assuming the count stays zero. A THIRD shape, plain
#   `ALTER ROLE r SET k=v` with no `IN DATABASE`, has `setdatabase = 0` —
#   genuinely cluster-wide, already
#   shared by every database including the clone, and correctly excluded
#   below (the `join pg_database` requires `setdatabase` to resolve to a
#   real row, which `0` never does).
#
# WHAT THIS DOES NOT COVER
#   - The plain `ALTER ROLE r SET k=v` shape above (`setdatabase = 0`) —
#     genuinely cluster-level, already shared, nothing to replay.
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

# --- Sec-required structural safety guard (2026-09-02 advisory) ---
# This script terminates backends and DROPs a database named $SCRATCH_NAME
# on $DB_HOST before every clone. Refuse anything but a local host unless
# the operator explicitly opts out, and refuse a scratch name that collides
# with a real Postgres database — including the template itself, since
# dropping "$TEMPLATE_NAME" here would destroy the very thing being cloned.
case "$DB_HOST" in
  127.0.0.1|localhost) ;;
  *)
    [ "${DB_TEMPLATE_ALLOW_REMOTE:-}" = "1" ] || die "DB_TEMPLATE_HOST='$DB_HOST' is not 127.0.0.1/localhost — refusing to run a destructive DROP DATABASE path against it. Set DB_TEMPLATE_ALLOW_REMOTE=1 if this is deliberate."
    log "WARNING: DB_TEMPLATE_ALLOW_REMOTE=1 — proceeding against non-local host '$DB_HOST'."
    ;;
esac
case "$SCRATCH_NAME" in
  postgres|template0|template1|"$TEMPLATE_NAME")
    die "refusing to use '$SCRATCH_NAME' as a scratch DB name — it collides with a protected database."
    ;;
esac

[ -d "$MIGRATIONS_DIR" ] || die "no $MIGRATIONS_DIR found — run from the repo root (or a worktree of it)."

# --- resolve the running container, same convention as db-template-build.sh
# / scripts/db-snapshot.sh — needed for the container_image_id staleness leg. ---
PROJECT_ID=""
if [ -f "supabase/config.toml" ]; then
  PROJECT_ID=$(grep -m1 -E '^project_id' supabase/config.toml | sed -E 's/^project_id[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
fi
if [ -n "$PROJECT_ID" ]; then
  CONTAINER="supabase_db_${PROJECT_ID}"
else
  CONTAINER=$(docker ps --filter "name=supabase_db_" --format '{{.Names}}' 2>/dev/null | head -n1)
fi
CURRENT_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || echo "unknown")

psql_as() {
  local dbname="$1"; shift
  psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$dbname" -v ON_ERROR_STOP=1 "$@"
}

# --- does the template even exist? ---
TEMPLATE_EXISTS=$(psql_as postgres -Atqc "select 1 from pg_database where datname = '$TEMPLATE_NAME';" 2>/dev/null || true)
[ "$TEMPLATE_EXISTS" = "1" ] || die "no '$TEMPLATE_NAME' template found. Run scripts/db-template-build.sh first (it does not run automatically on every check-out — see docs/db-template.md)."

# --- staleness fence: compare the template's marker to the CURRENT tree ---
# Three legs: head migration filename, sha256 of the full migrations tree,
# and (Sec advisory 2026-09-02) the container image id the template's
# auth/extensions/vault schema was dumped from — a CLI/image upgrade can
# change that schema with zero change to the migrations tree, which the
# first two legs alone cannot see. None of these three values can contain
# '|', so a plain-pipe join/split is safe here (unlike the setting replay
# below, which uses chr(31) because a GUC value could contain one).
MARKER=$(psql_as "$TEMPLATE_NAME" -Atqc "select head_migration || '|' || content_sha256 || '|' || coalesce(container_image_id, '') from public._template_meta;" 2>/dev/null || true)
[ -n "$MARKER" ] || die "'$TEMPLATE_NAME' exists but carries no public._template_meta marker — it did not come from db-template-build.sh, or was built by an older version of it. Rebuild: scripts/db-template-build.sh."

TEMPLATE_HEAD=$(echo "$MARKER" | cut -d'|' -f1)
TEMPLATE_SHA=$(echo "$MARKER" | cut -d'|' -f2)
TEMPLATE_IMAGE_ID=$(echo "$MARKER" | cut -d'|' -f3)

CURRENT_HEAD=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \; | sort | tail -n1)
CURRENT_SHA=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z | xargs -0 cat | shasum -a 256 | awk '{print $1}')

STALE=0
[ "$TEMPLATE_HEAD" != "$CURRENT_HEAD" ] && STALE=1
[ "$TEMPLATE_SHA" != "$CURRENT_SHA" ] && STALE=1
# container_image_id is an OLDER-marker-tolerant leg, not a hard requirement:
# a template built before this field existed carries an empty string (older
# CREATE TABLE ran with no such column and this script's own coalesce reads
# it as ''), which would false-positive against every current container.
# Only compare it when the template actually stamped one.
if [ -n "$TEMPLATE_IMAGE_ID" ] && [ "$TEMPLATE_IMAGE_ID" != "$CURRENT_IMAGE_ID" ]; then
  STALE=1
  log "container image id changed since build: template=$TEMPLATE_IMAGE_ID current=$CURRENT_IMAGE_ID"
fi

if [ "$STALE" -eq 1 ]; then
  die "'$TEMPLATE_NAME' is STALE — refusing to clone.
    template:  head=$TEMPLATE_HEAD  sha256=$TEMPLATE_SHA  image=$TEMPLATE_IMAGE_ID
    tree now:  head=$CURRENT_HEAD  sha256=$CURRENT_SHA  image=$CURRENT_IMAGE_ID
  Run scripts/db-template-build.sh to refresh, then retry."
fi
log "staleness check passed (head=$CURRENT_HEAD, sha256=$CURRENT_SHA, image=$CURRENT_IMAGE_ID)."

# --- the fast path: template clone ---
psql_as postgres -Atqc "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$SCRATCH_NAME' and pid <> pg_backend_pid();" >/dev/null 2>&1 || true
psql_as postgres -Atqc "drop database if exists \"$SCRATCH_NAME\";" >/dev/null
createdb -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" --template="$TEMPLATE_NAME" "$SCRATCH_NAME"
log "cloned $TEMPLATE_NAME -> $SCRATCH_NAME."

# --- replay pg_db_role_setting rows keyed to THIS SPECIFIC database OID ---
# Both shapes documented in the header (`ALTER DATABASE d SET`, setrole=0;
# and `ALTER ROLE r IN DATABASE d SET`, setrole<>0) — NOT just the first one.
# `setconfig` entries look like "TimeZone=UTC" / "key=value"; split on the
# FIRST '=' only (a value could itself contain '=', e.g. a DSN). Fields are
# separated with chr(31) (ASCII unit separator), not '|' or a comma, since a
# role name or setting value could in principle contain either.
ROWS=$(psql_as postgres -Atqc "
  select coalesce(r.rolname, '') || chr(31) || unnest(drs.setconfig)
    from pg_db_role_setting drs
    join pg_database d on d.oid = drs.setdatabase
    left join pg_roles r on r.oid = drs.setrole
   where d.datname = '$TEMPLATE_NAME';
" 2>/dev/null || true)

if [ -n "$ROWS" ]; then
  while IFS=$'\x1f' read -r rolename kv; do
    [ -z "$kv" ] && continue
    key="${kv%%=*}"
    val="${kv#*=}"
    if [ -z "$rolename" ]; then
      log "replaying per-database setting onto clone: $key"
      psql_as postgres -v ON_ERROR_STOP=1 -c "alter database \"$SCRATCH_NAME\" set \"$key\" = '$val';" >/dev/null
    else
      log "replaying per-role-per-database setting onto clone: $rolename / $key"
      psql_as postgres -v ON_ERROR_STOP=1 -c "alter role \"$rolename\" in database \"$SCRATCH_NAME\" set \"$key\" = '$val';" >/dev/null
    fi
  done <<< "$ROWS"
else
  log "template carries no database-scoped pg_db_role_setting entries — nothing to replay."
fi

log "done. $SCRATCH_NAME is ready (head=$CURRENT_HEAD)."
