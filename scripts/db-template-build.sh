#!/usr/bin/env bash
#
# db-template-build.sh — build (or refresh) the fully-migrated template
# database, DevOps-owned, per F/CTO-ratified loop-mechanics option A
# (2026-09-02 sitting).
#
# WHY THIS EXISTS
#   Every QA/Architect verification pass rebuilds a scratch DB by applying
#   supabase/migrations/001..0NN sequentially — the single biggest per-issue
#   time sink measured across four recent arcs (see
#   .claude/agent-memory/architect/reference_scratch_db_full_chain_recipe.md
#   and reference_scratch_db_for_migration_verify.md for the recipe this
#   script automates). This script runs that same sequential chain ONCE and
#   leaves the result as a Postgres TEMPLATE database (`pfin_tmpl`) that
#   db-template-clone.sh can clone in seconds via `createdb --template`,
#   instead of re-applying ~100 migration files every time.
#
# WHAT IT DOES NOT DO
#   It does not decide when to run. That is a separate concern (see the
#   companion `.husky/post-merge` hook, and the report this shipped with for
#   the CI-artifact alternative that was NOT adopted). This script is safe to
#   run by hand, any time, and is idempotent — a stale template is a
#   liveness problem the clone script fails loudly on (see
#   db-template-clone.sh), never a correctness one.
#
# RECIPE (mirrors the QA/Architect "full chain" recipe verbatim; deviating
# from it silently would reintroduce the exact traps that recipe documents)
#   1. Dump auth/extensions/vault/graphql/net/storage/supabase_functions
#      schema-only from the running local stack's Postgres container, using
#      the CONTAINER's pg_dump (the host's Homebrew pg_dump is a major
#      version behind the 17.x server and refuses the dump outright).
#      Deliberately NOT --no-privileges and NOT --no-owner: those flags drop
#      REVOKEs as well as GRANTs, which would make the template MORE
#      PERMISSIVE than the real bootstrap and any privilege-denial assertion
#      run against a clone of it would pass vacuously. This is the
#      "--no-privileges trap" this whole exercise is disqualified by
#      reintroducing.
#   2. Load that dump into a candidate DB as supabase_admin (the dump does
#      `ALTER SCHEMA auth OWNER TO supabase_admin`; `postgres` cannot SET
#      ROLE to it, so loading as `postgres` dies on the first statement).
#   3. Create extensions (uuid-ossp, pgcrypto, pg_net, supabase_vault) AFTER
#      the load, into the schemas the dump already created — creating them
#      before the load makes the dump's own `CREATE SCHEMA extensions` fail.
#   4. Hand the candidate DB to `postgres` (`ALTER DATABASE ... OWNER TO
#      postgres`) BEFORE applying migrations — in the real stack every pfin
#      table is postgres-owned, and applying as postgres against a
#      supabase_admin-owned DB fails immediately (postgres can't even
#      `CREATE SCHEMA` there).
#   5. Apply supabase/migrations/*.sql in sorted numeric order as postgres,
#      ON_ERROR_STOP=1.
#   6. `CREATE EXTENSION pgtap SCHEMA public` — public, not extensions:
#      `authenticated`/`anon`/`service_role` don't carry postgres's
#      role-level search_path override, so a pgtap installed in `extensions`
#      goes invisible ("function is(...) does not exist") the moment a test
#      file switches role.
#   7. Stamp a marker table (public._template_meta) with the head migration
#      filename, a sha256 of the full migrations tree, the migration count,
#      the running container's image id, and the build timestamp — this is
#      the staleness fence db-template-clone.sh checks before ever cloning.
#      The image id matters because the auth/extensions/vault schema this
#      template bakes in comes from the CONTAINER (step 1), not from
#      supabase/migrations/ — a CLI/image upgrade can change it with zero
#      change to the migrations tree, invisible to the other two fields.
#   8. Atomically swap: terminate any sessions on the OLD `pfin_tmpl` (if a
#      prior template exists), drop it, rename the verified candidate into
#      its place. Never rename before the candidate is verified — a partial
#      or failed build is dropped, never promoted.
#
# GAP THIS INTENTIONALLY DOES NOT CLOSE HERE (closed in db-template-clone.sh
# instead): `CREATE DATABASE ... TEMPLATE` does NOT copy `pg_db_role_setting`
# — a shared catalog keyed by database OID, so a templated clone gets a new
# OID and no row at all. Migration 061's `ALTER DATABASE current_database()
# SET TimeZone = 'UTC'` therefore lands correctly HERE (this script runs the
# real sequential chain, exactly like a from-scratch scratch DB would), but a
# `createdb --template=pfin_tmpl` clone of this result would silently NOT
# inherit it — QA measured this exact gap 2026-08-19 (085) via a template
# clone that lost the TimeZone pin. db-template-clone.sh replays every
# `pg_db_role_setting` row this template carries (whatever they are —
# generic, not hardcoded to TimeZone) onto every clone it makes, which is why
# that gap is a clone-time concern and not rebuilt into this file.
#
# USAGE
#   scripts/db-template-build.sh
#
# This script is NOT wired to run automatically by itself — see
# .husky/post-merge for the trigger, and docs/db-template.md for the full
# picture (refresh trigger, staleness fence, restore/replay mechanics).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_HOST="${DB_TEMPLATE_HOST:-127.0.0.1}"
DB_PORT="${DB_TEMPLATE_PORT:-54322}"
SUPERUSER="${DB_TEMPLATE_SUPERUSER:-postgres}"
TEMPLATE_NAME="${DB_TEMPLATE_NAME:-pfin_tmpl}"
MIGRATIONS_DIR="supabase/migrations"
# Local Supabase dev stack default (both `postgres` and `supabase_admin`) —
# override via DB_TEMPLATE_PASSWORD for any environment where it differs.
export PGPASSWORD="${DB_TEMPLATE_PASSWORD:-postgres}"

log() { echo "[db-template-build] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# --- Sec-required structural safety guard (2026-09-02 advisory) ---
# This script DROPs/renames databases on $DB_HOST, and the .husky/post-merge
# hook calls it automatically on every local merge touching migrations — so
# a misconfigured DB_TEMPLATE_HOST or DB_TEMPLATE_NAME turns an automated,
# unattended local hook into a destructive action against the wrong target.
# Refuse anything but a local host unless the operator explicitly opts out,
# and refuse to ever build/swap into a name that collides with a real
# Postgres database.
case "$DB_HOST" in
  127.0.0.1|localhost) ;;
  *)
    [ "${DB_TEMPLATE_ALLOW_REMOTE:-}" = "1" ] || die "DB_TEMPLATE_HOST='$DB_HOST' is not 127.0.0.1/localhost — refusing to run a destructive DROP/CREATE DATABASE path against it. Set DB_TEMPLATE_ALLOW_REMOTE=1 if this is deliberate."
    log "WARNING: DB_TEMPLATE_ALLOW_REMOTE=1 — proceeding against non-local host '$DB_HOST'."
    ;;
esac
case "$TEMPLATE_NAME" in
  postgres|template0|template1)
    die "DB_TEMPLATE_NAME='$TEMPLATE_NAME' collides with a protected database name — refusing to build/swap into it."
    ;;
esac

[ -d "$MIGRATIONS_DIR" ] || die "no $MIGRATIONS_DIR found — run from the repo root (or a worktree of it)."

# --- resolve the running container, same convention as scripts/db-snapshot.sh ---
PROJECT_ID=""
if [ -f "supabase/config.toml" ]; then
  PROJECT_ID=$(grep -m1 -E '^project_id' supabase/config.toml | sed -E 's/^project_id[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
fi
if [ -n "$PROJECT_ID" ]; then
  CONTAINER="supabase_db_${PROJECT_ID}"
else
  CONTAINER=$(docker ps --filter "name=supabase_db_" --format '{{.Names}}' 2>/dev/null | head -n1)
fi
[ -n "${CONTAINER:-}" ] || die "no supabase_db_* container found — is the local stack up?"
[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ] || die "$CONTAINER is not running."

# Image id of the running container, stamped into the marker alongside the
# migration-tree fingerprint (Sec advisory, 2026-09-02). The migrations tree
# is not the only thing that can change the auth/extensions/vault schema
# this template dumps — a Supabase CLI / postgres image upgrade can too,
# with zero change to supabase/migrations/, which the existing fence
# structurally cannot see. Stamping the image id lets db-template-clone.sh
# catch that case too.
CONTAINER_IMAGE_ID=$(docker inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null || echo "unknown")

command -v psql >/dev/null 2>&1 || die "host psql not found (createdb/dropdb/psql from the Postgres client tools are required on the host)."

# psql_as <dbname> [psql args...] — always explicit about which database,
# never relying on a later -d silently overriding an earlier one in a shared array.
# Connects as $SUPERUSER (postgres) — for reading/writing INSIDE a database
# postgres already owns.
psql_as() {
  local dbname="$1"; shift
  psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$dbname" -v ON_ERROR_STOP=1 "$@"
}

# psql_admin [psql args...] — administrative operations (terminate backends,
# DROP DATABASE, ALTER DATABASE ... OWNER TO / RENAME TO) that must succeed
# regardless of which role currently owns the target. Always as supabase_admin
# (real superuser, rolsuper=t) against the postgres maintenance DB — postgres
# itself is NOT superuser (rolsuper=f) and can only act on databases it
# already owns, which is exactly the DB-in-transition case these calls cover.
# Measured: doing this as $SUPERUSER instead produced "ERROR: must be owner
# of database" on the ownership handoff, and a silently-failed (`|| true`
# masked) DROP DATABASE in cleanup, leaking a stray pfin_tmpl_build_* database.
psql_admin() {
  psql -X -h "$DB_HOST" -p "$DB_PORT" -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"
}
dropdb_admin() {
  dropdb -h "$DB_HOST" -p "$DB_PORT" -U supabase_admin "$@"
}

# --- staleness inputs: computed once, embedded in the marker table ---
# Portable (no GNU-only `find -printf`, which BSD/macOS find lacks).
HEAD_MIGRATION=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \; | sort | tail -n1)
[ -n "$HEAD_MIGRATION" ] || die "no migration files found under $MIGRATIONS_DIR."
CONTENT_SHA=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z | xargs -0 cat | shasum -a 256 | awk '{print $1}')
MIGRATION_COUNT=$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')

log "head migration: $HEAD_MIGRATION ($MIGRATION_COUNT files, sha256 $CONTENT_SHA)"

CANDIDATE="pfin_tmpl_build_$(date +%s)"
AUTH_DUMP_FILE=$(mktemp)
SWAPPED=0

# Single combined EXIT trap: always remove the scratch dump file; on a
# non-zero exit BEFORE the swap completed, also drop the half-built
# candidate so failed runs don't accumulate garbage databases. A trap
# defined a second time REPLACES the first (a real gotcha — keep this as
# one handler, not two `trap ... EXIT` calls).
cleanup() {
  rc=$?
  rm -f "$AUTH_DUMP_FILE"
  if [ "$rc" -ne 0 ] && [ "$SWAPPED" -eq 0 ]; then
    log "cleaning up failed candidate $CANDIDATE"
    psql_admin -Atqc "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$CANDIDATE' and pid <> pg_backend_pid();" >/dev/null 2>&1 || true
    dropdb_admin --if-exists "$CANDIDATE" >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

# --- 1. dump auth/extensions/vault/etc from the container, FULL posture ---
log "dumping auth/extensions/vault/graphql/net/storage/supabase_functions (privileges preserved)"
docker exec "$CONTAINER" pg_dump -U "$SUPERUSER" -d postgres --schema-only \
  --schema=auth --schema=extensions --schema=vault --schema=graphql \
  --schema=net --schema=storage --schema=supabase_functions \
  > "$AUTH_DUMP_FILE"
[ -s "$AUTH_DUMP_FILE" ] || die "auth-schema dump came back empty."

# --- 2. create candidate DB and load the dump AS supabase_admin ---
log "creating candidate database $CANDIDATE (owner supabase_admin for the load)"
createdb -h "$DB_HOST" -p "$DB_PORT" -U supabase_admin -O supabase_admin "$CANDIDATE"
psql -X -h "$DB_HOST" -p "$DB_PORT" -U supabase_admin -d "$CANDIDATE" -v ON_ERROR_STOP=1 -q -f "$AUTH_DUMP_FILE"

# --- 3. extensions, post-load, into the schemas the dump made ---
log "creating extensions (uuid-ossp, pgcrypto, pg_net, supabase_vault)"
psql -X -h "$DB_HOST" -p "$DB_PORT" -U supabase_admin -d "$CANDIDATE" -v ON_ERROR_STOP=1 <<'SQL'
create extension if not exists "uuid-ossp" schema extensions;
create extension if not exists pgcrypto schema extensions;
create extension if not exists pg_net schema extensions;
create extension if not exists supabase_vault schema vault cascade;
SQL

# --- 4. hand the DB to postgres before applying migrations ---
# Must run as supabase_admin (superuser, and current owner of $CANDIDATE) —
# $SUPERUSER (postgres) is neither superuser nor the owner yet, so it cannot
# reassign ownership to itself. Measured: "ERROR: must be owner of database".
log "transferring candidate ownership to $SUPERUSER"
psql_admin -c "alter database \"$CANDIDATE\" owner to $SUPERUSER;"

# --- 5. apply the full migration chain, sorted, as postgres ---
log "applying $MIGRATION_COUNT migrations..."
i=0
while IFS= read -r mig; do
  i=$((i + 1))
  psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$CANDIDATE" -v ON_ERROR_STOP=1 -q -f "$mig"
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)
log "applied $i migrations clean."

# --- 6. pgtap in public (not extensions) ---
psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$CANDIDATE" -v ON_ERROR_STOP=1 \
  -c "create extension if not exists pgtap schema public;"

# --- 7. marker table: the staleness fence db-template-clone.sh reads ---
# container_image_id (Sec advisory 2026-09-02): the auth/extensions/vault
# schema this template bakes in comes from the CONTAINER, not from
# supabase/migrations/ — a CLI/image upgrade can change it with zero change
# to the migrations tree, which head_migration/content_sha256 alone cannot
# see. Stamped alongside them so db-template-clone.sh can catch that case
# too.
psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$SUPERUSER" -d "$CANDIDATE" -v ON_ERROR_STOP=1 <<SQL
create table if not exists public._template_meta (
  head_migration       text        not null,
  content_sha256       text        not null,
  migration_count      integer     not null,
  container_image_id   text        not null,
  built_at             timestamptz not null default now()
);
truncate public._template_meta;
insert into public._template_meta (head_migration, content_sha256, migration_count, container_image_id)
values ('$HEAD_MIGRATION', '$CONTENT_SHA', $MIGRATION_COUNT, '$CONTAINER_IMAGE_ID');
SQL

log "candidate built and stamped. Verifying before swap..."
ROWCOUNT=$(psql_as "$CANDIDATE" -Atqc "select count(*) from public._template_meta;" 2>/dev/null || echo 0)
[ "$ROWCOUNT" = "1" ] || die "marker table verification failed (expected 1 row, got '$ROWCOUNT') — refusing to promote."

# --- 8. atomic-ish swap: terminate + drop old template, rename candidate in ---
log "swapping candidate into $TEMPLATE_NAME"
psql_admin -Atqc "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$TEMPLATE_NAME' and pid <> pg_backend_pid();" >/dev/null 2>&1 || true
dropdb_admin --if-exists "$TEMPLATE_NAME"
psql_admin -c "alter database \"$CANDIDATE\" rename to \"$TEMPLATE_NAME\";"
SWAPPED=1

log "done. $TEMPLATE_NAME is head_migration=$HEAD_MIGRATION content_sha256=$CONTENT_SHA container_image_id=$CONTAINER_IMAGE_ID ($MIGRATION_COUNT migrations)."
