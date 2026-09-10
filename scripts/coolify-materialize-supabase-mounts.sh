#!/usr/bin/env bash
#
# coolify-materialize-supabase-mounts.sh — materialize infra/supabase/volumes/**
# onto the Coolify host as real files, and sync Coolify's local_file_volumes
# bookkeeping to match. DevOps-owned, `docs/deployment-runbook.md` §4.
#
# WHY THIS EXISTS
#   The pfin-supabase-stack Coolify resource (build_pack=dockercompose,
#   is_preserve_repository_enabled=false — the default) hits every relative
#   bind mount in infra/supabase/docker-compose.yml through
#   bootstrap/helpers/parsers.php's applicationParser(): it rewrites each
#   `./volumes/...` source to an absolute host path under
#   /data/coolify/applications/<uuid>/volumes/... and records that path in a
#   `local_file_volumes` row, defaulting `is_directory=true` the first time
#   it sees a mount path it has no row for. Nothing in
#   ApplicationDeploymentJob's non-preserve-repository path ever calls
#   LocalFileVolume::saveStorageOnServer() to correct that guess — that only
#   fires when is_preserve_repository_enabled is on. So the FIRST deploy
#   leaves every file-shaped bind mount pre-created as an empty host
#   directory, and Docker refuses to bind an empty directory onto a
#   container-side file path ("not a directory: Are you trying to mount a
#   directory onto a file?"). This script is the reproducible substitute for
#   the correction step Coolify's own deploy flow skips in this build_pack.
#
#   It also fixes local_file_volumes.content and .is_directory through
#   Coolify's own Eloquent model (via `php artisan tinker` inside the
#   `coolify` container), never with a raw SQL UPDATE — LocalFileVolume casts
#   `content` as `encrypted`; writing plaintext into that column directly
#   would corrupt it (Coolify throws decrypting it on next read).
#
# WHAT IT REFUSES TO DO
#   - Never edits infra/supabase/volumes/** — that tree is vendored upstream
#     content and the single source of truth (see infra/supabase/README.md).
#     This script only ever reads from it.
#   - Only ever removes a stale mount directory with `rmdir`, which fails on
#     anything non-empty. It will not force-delete a directory that has
#     unexpected contents; it stops and reports instead.
#   - Default is --dry-run (prints the plan, touches nothing). Requires
#     --apply to write anything, on the box or in Coolify's database.
#
# IDEMPOTENCE
#   Re-running after a fresh deploy attempt, or after infra/supabase/volumes/**
#   changes on a re-vendor, is safe: each file is fully overwritten from the
#   repo's copy and each local_file_volumes row is fully overwritten to match.
#
# USAGE
#   scripts/coolify-materialize-supabase-mounts.sh --apply
#
# ENV OVERRIDES (defaults match the pfin-supabase-stack production resource)
#   COOLIFY_APP_UUID   default: eepvlmaq4uortakmido7jgvn
#   COOLIFY_SSH_HOST    default: root@188.245.166.206
#   COOLIFY_SSH_KEY     default: ~/.ssh/id_ed25519_claude_mosko-fintech

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOLUMES_DIR="$REPO_ROOT/infra/supabase/volumes"
APP_UUID="${COOLIFY_APP_UUID:-eepvlmaq4uortakmido7jgvn}"
SSH_HOST="${COOLIFY_SSH_HOST:-root@188.245.166.206}"
SSH_KEY="${COOLIFY_SSH_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
APPLY=false

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --dry-run) APPLY=false ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# mount_path (container target, corrected) | path relative to $VOLUMES_DIR | stale mount_path this row may still carry
MANIFEST='
/etc/envoy/envoy.yaml|api/envoy/envoy.yaml|
/etc/envoy/cds.yaml|api/envoy/cds.yaml|
/etc/envoy/lds.template.yaml|api/envoy/lds.template.yaml|
/docker-entrypoint.sh|api/envoy/docker-entrypoint.sh|
/docker-entrypoint-initdb.d/migrations/99-realtime.sql|db/realtime.sql|
/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql|db/webhooks.sql|
/docker-entrypoint-initdb.d/init-scripts/99-roles.sql|db/roles.sql|
/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql|db/jwt.sql|
/docker-entrypoint-initdb.d/migrations/97-_supabase.sql|db/_supabase.sql|
/docker-entrypoint-initdb.d/migrations/99-logs.sql|db/logs.sql|
/docker-entrypoint-initdb.d/migrations/99-pooler.sql|db/pooler.sql|
/etc/pooler/pooler.exs|pooler/pooler.exs|/etc/pooler/pooler.exs:ro,z
'

echo "==> Preflight: checking all ${VOLUMES_DIR#"$REPO_ROOT"/} files referenced by the manifest exist"
while IFS='|' read -r mount_path rel_path stale_mount; do
  [ -z "$mount_path" ] && continue
  [ -f "$VOLUMES_DIR/$rel_path" ] || { echo "MISSING: $VOLUMES_DIR/$rel_path" >&2; exit 1; }
done <<<"$MANIFEST"
echo "    ok — 12 files present"

if [ "$APPLY" != true ]; then
  echo "==> Dry run only (pass --apply to execute). Plan:"
  echo "    1. scp infra/supabase/volumes/** to $SSH_HOST:/tmp/pfin-supabase-mounts"
  echo "    2. On the box: rmdir each stale bogus mount directory (fails if non-empty), cp the real file into place, chmod 644 (755 for docker-entrypoint.sh)"
  echo "    3. Sync local_file_volumes.content + is_directory=false for all 12 rows via php artisan tinker inside the coolify container (Eloquent, not raw SQL — content is encrypted-cast)"
  echo "    4. Clean up the staged /tmp copy"
  exit 0
fi

echo "==> Staging infra/supabase/volumes/** on $SSH_HOST"
ssh -i "$SSH_KEY" "$SSH_HOST" "mkdir -p /tmp/pfin-supabase-mounts"
scp -i "$SSH_KEY" -rq "$VOLUMES_DIR/." "$SSH_HOST:/tmp/pfin-supabase-mounts/"

echo "==> Materializing real files at Coolify's tracked fs_path (replacing any bogus empty directory)"
REMOTE_MATERIALIZE=$(cat <<REMOTESCRIPT
set -euo pipefail
APP_HOME="/data/coolify/applications/$APP_UUID"
SRC="/tmp/pfin-supabase-mounts"
while IFS='|' read -r mount_path rel_path stale_mount; do
  [ -z "\$mount_path" ] && continue
  fs_path="\$APP_HOME/volumes/\$rel_path"
  mkdir -p "\$(dirname "\$fs_path")"
  if [ -d "\$fs_path" ]; then rmdir "\$fs_path"; fi
  cp "\$SRC/\$rel_path" "\$fs_path"
  chmod 644 "\$fs_path"
  echo "materialized \$fs_path (\$(stat -c '%F' "\$fs_path"))"
done <<'MANIFEST_EOF'
$MANIFEST
MANIFEST_EOF
chmod 755 "\$APP_HOME/volumes/api/envoy/docker-entrypoint.sh"
REMOTESCRIPT
)
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s <<<"$REMOTE_MATERIALIZE"

echo "==> Syncing local_file_volumes rows through Coolify's Eloquent model"
PHP_SCRIPT="$(mktemp)"
{
  echo "\$app = \\App\\Models\\Application::where('uuid', '$APP_UUID')->firstOrFail();"
  echo '$manifest = ['
  while IFS='|' read -r mount_path rel_path stale_mount; do
    [ -z "$mount_path" ] && continue
    content_b64="$(base64 < "$VOLUMES_DIR/$rel_path" | tr -d '\n')"
    if [ -n "$stale_mount" ]; then
      stale_php="'$(printf '%s' "$stale_mount" | sed "s/'/\\\\'/g")'"
    else
      stale_php="null"
    fi
    printf "  ['%s', %s, base64_decode('%s')],\n" "$mount_path" "$stale_php" "$content_b64"
  done <<<"$MANIFEST"
  echo '];'
  cat <<'PHPBODY'
foreach ($manifest as [$mount, $staleMount, $content]) {
  $row = \App\Models\LocalFileVolume::where('resource_id', $app->id)
      ->where('resource_type', get_class($app))
      ->where('mount_path', $mount)->first();
  if (!$row && $staleMount) {
    $row = \App\Models\LocalFileVolume::where('resource_id', $app->id)
        ->where('resource_type', get_class($app))
        ->where('mount_path', $staleMount)->first();
  }
  if (!$row) { echo "MISSING ROW for $mount\n"; continue; }
  $row->mount_path = $mount;
  $row->content = $content;
  $row->is_directory = false;
  $row->save();
  echo "synced $mount (id={$row->id}, bytes=" . strlen($content) . ")\n";
}
PHPBODY
} > "$PHP_SCRIPT"

ssh -i "$SSH_KEY" "$SSH_HOST" "docker exec -i coolify php artisan tinker" < "$PHP_SCRIPT"
rm -f "$PHP_SCRIPT"

echo "==> Cleaning up staged copy on the box"
ssh -i "$SSH_KEY" "$SSH_HOST" "rm -rf /tmp/pfin-supabase-mounts"

echo "==> Done. Redeploy the pfin-supabase-stack application for the fix to take effect if a deploy hasn't run since."
